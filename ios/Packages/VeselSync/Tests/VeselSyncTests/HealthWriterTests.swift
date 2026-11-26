import Foundation
import Synchronization
import Testing
import VeselCore
@testable import VeselStorage
@testable import VeselSync

/// Apple Health as HealthKit behaves for Vesel's own samples: a save with a sync id already there replaces it only with a
/// higher version; a removal takes the unit's objects below a version.
actor FakeHealth: HealthStore {
    struct Object: Equatable {
        var item: HealthItem
        var unit: String
        var version: Int64
    }

    private(set) var objects: [String: Object] = [:]
    private(set) var calls: [String] = []
    var access: [HealthKind: HealthAccess]
    /// What the sheet leaves when Vesel asks.
    var afterAsking: [HealthKind: HealthAccess]?
    var saveError: HealthStoreError?

    init(access: [HealthKind: HealthAccess] = Dictionary(uniqueKeysWithValues: HealthKind.allCases.map { ($0, .allowed) })) {
        self.access = access
    }

    func set(access: [HealthKind: HealthAccess]) { self.access = access }
    func set(afterAsking: [HealthKind: HealthAccess]) { self.afterAsking = afterAsking }
    func set(saveError: HealthStoreError?) { self.saveError = saveError }

    func authorization() -> [HealthKind: HealthAccess] { access }

    func requestAuthorization() {
        calls.append("ask")
        if let afterAsking { access = afterAsking }
    }

    func save(_ items: [HealthItem], unit: HealthUnit, version: Int64) throws {
        if let saveError { throw saveError }
        calls.append("save \(unit.id)")
        for item in items where (objects[item.syncId]?.version ?? -1) < version {
            objects[item.syncId] = Object(item: item, unit: unit.id, version: version)
        }
    }

    func removeStale(unit: HealthUnit, kind: HealthKind, below version: Int64) {
        calls.append("remove \(unit.id)")
        objects = objects.filter { $0.value.unit != unit.id || $0.value.version >= version }
    }

    func ids(_ type: HealthType) -> [String] {
        objects.values.filter { $0.item.type == type }.map(\.item.syncId).sorted()
    }
}

/// Berlin is UTC+1 on 2026-10-27.
struct HealthWriterTests {
    let berlin = TimeZone(identifier: "Europe/Berlin")!
    let database: AppDatabase
    let night = DayKey("2026-10-27")!

    init() async throws {
        database = try AppDatabase.inMemory()
        try await database.setHealthWrite(true)
        try await heartRates(on: "2026-10-26", readAt: "2026-10-27T08:00:00Z")
        try await heartRates(on: "2026-10-27", readAt: "2026-10-27T08:00:00Z")
        try await sleep(["LIGHT", "DEEP"], readAt: "2026-10-27T08:00:00Z")
    }

    func heartRates(on day: String, readAt: String) async throws {
        let payload = BandPayload(
            day: DayKey(day)!, kind: .heartRate,
            json: #"{"date":"\#(day)","samples":[{"hr":60,"time":"06:00:00","triggerType":"TIMED"},{"hr":62,"time":"06:05:00","triggerType":"TIMED"}]}"#,
            utcOffsetSeconds: 3600, sampleCount: 2)
        try await database.save([payload], fetchedAt: at(readAt))
    }

    /// Phases an hour apart from 23:00 to 07:00.
    func sleep(_ states: [String], readAt: String) async throws {
        let phases = states.enumerated().map { #"{"secondsFromSleepStart":\#($0 * 3600),"state":"\#($1)"}"# }.joined(separator: ",")
        let payload = BandPayload(
            day: night, kind: .sleep,
            json: #"{"sleepResultDate":"2026-10-27","sleepStartTime":"2026-10-26T23:00:00+01:00","sleepEndTime":"2026-10-27T07:00:00+01:00","sleepGoalMinutes":480,"sleepWakePhases":[\#(phases)]}"#,
            utcOffsetSeconds: 3600, sampleCount: states.count)
        try await database.save([payload], fetchedAt: at(readAt))
    }

    func writer(_ health: FakeHealth, at iso: String) -> HealthWriter {
        HealthWriter(database: database, store: health, clock: FixedClock(now: at(iso), timeZone: berlin))
    }

    func run(_ health: FakeHealth, at iso: String, ask: Bool = false, unlocked: @escaping @Sendable () -> Bool = { true }) async -> HealthRunOutcome {
        await writer(health, at: iso).run(askForNewKinds: ask, isProtectedDataAvailable: unlocked)
    }

    @Test func theFirstRunWritesAllHistoryNewestFirstAndTheNextWritesNothing() async throws {
        let health = FakeHealth()

        #expect(await run(health, at: "2026-10-27T09:00:00Z") == .upToDate)

        #expect(
            await health.calls == [
                "save heartRate/2026-10-27", "remove heartRate/2026-10-27", "save sleep/2026-10-27", "remove sleep/2026-10-27",
                "save heartRate/2026-10-26", "remove heartRate/2026-10-26",
            ])
        #expect(await health.ids(.heartRate).count == 4)
        #expect(await health.ids(.sleep) == ["vesel.sleep.2026-10-27.1793052000", "vesel.sleep.2026-10-27.1793055600", "vesel.sleep.2026-10-27.inBed"])
        #expect(await health.objects.values.allSatisfy { $0.version == 1_793_091_600_000 })
        #expect(try await database.healthStatus().lastRun == HealthRun(at: at("2026-10-27T09:00:00Z"), outcome: .written, daysToGo: 0, notAllowed: [], wroteAny: true))

        #expect(await run(health, at: "2026-10-27T10:00:00Z") == .upToDate)
        #expect(await health.calls.count == 6)
    }

    @Test func aLaterReadIsSavedFirstThenTheOldCopiesGo() async throws {
        let health = FakeHealth()
        _ = await run(health, at: "2026-10-27T09:00:00Z")

        try await sleep(["LIGHT", "REM", "DEEP"], readAt: "2026-10-27T09:30:00Z")
        #expect(await run(health, at: "2026-10-27T10:00:00Z") == .upToDate)

        #expect(await health.calls.suffix(2) == ["save sleep/2026-10-27", "remove sleep/2026-10-27"])
        #expect(await health.ids(.sleep).count == 4)
        let versions = await health.objects.values.filter { $0.unit == "sleep/2026-10-27" }.map(\.version)
        #expect(versions.allSatisfy { $0 == 1_793_095_200_000 })
    }

    /// The night's resting heart rate went (Polar withdrew it): its copy is removed and its bookkeeping forgotten.
    @Test func aUnitWhoseDataWentIsRemoved() async throws {
        try await database.save(
            ComputedMetric(
                kind: Contributor.restingHeartRate.kind, day: night, hour: nil, value: 52, unit: "bpm",
                explanation: Explanation(method: RecoveryContributors.method, version: RecoveryContributors.version, inputs: [], text: ""),
                computedAt: at("2026-10-27T08:00:00Z")))
        let health = FakeHealth()
        _ = await run(health, at: "2026-10-27T09:00:00Z")
        #expect(await health.ids(.restingHeartRate) == ["vesel.restingHR.2026-10-27"])

        try await database.writer.write { try $0.execute(sql: "DELETE FROM computed_metric") }
        #expect(await run(health, at: "2026-10-27T10:00:00Z") == .upToDate)

        #expect(await health.calls.last == "remove restingHeartRate/2026-10-27")
        #expect(await health.ids(.restingHeartRate).isEmpty)
        #expect(try await database.pendingHealthUnits(kinds: Set(HealthKind.allCases), zone: berlin).isEmpty)
    }

    @Test func aLockedPhoneWritesNothingAndTheNextRunCatchesUp() async throws {
        let health = FakeHealth()

        #expect(await run(health, at: "2026-10-27T09:00:00Z", unlocked: { false }) == .waitingForUnlock)
        #expect(await health.calls.isEmpty)
        #expect(try await database.pendingHealthUnits(kinds: Set(HealthKind.allCases), zone: berlin).count == 3)

        #expect(await run(health, at: "2026-10-27T10:00:00Z") == .upToDate)
        #expect(await health.ids(.heartRate).count == 4)
    }

    /// Locked after the first unit: the rest waits, and the days left are kept for Loop & settings.
    @Test func lockingDuringARunStopsBetweenUnits() async throws {
        let health = FakeHealth()
        let checks = Counter()

        let outcome = await run(health, at: "2026-10-27T09:00:00Z", unlocked: { checks.next() <= 2 })

        #expect(outcome == .waitingForUnlock)
        #expect(await health.calls == ["save heartRate/2026-10-27", "remove heartRate/2026-10-27"])
        #expect(try await database.healthStatus().lastRun?.outcome == .waitingForUnlock)
        #expect(try await database.healthStatus().lastRun?.daysToGo == 2)
    }

    @Test func healthSayingLockedStopsTheRunWithEverythingStillPending() async throws {
        let health = FakeHealth()
        await health.set(saveError: .locked)

        #expect(await run(health, at: "2026-10-27T09:00:00Z") == .waitingForUnlock)
        #expect(try await database.pendingHealthUnits(kinds: Set(HealthKind.allCases), zone: berlin).count == 3)
    }

    @Test func kindsNotAllowedOrNotAskedWaitUntilAllowed() async throws {
        let health = FakeHealth(access: [.heartRate: .allowed, .sleep: .denied, .steps: .notAsked, .restingHeartRate: .allowed, .respiratoryRate: .allowed])

        _ = await run(health, at: "2026-10-27T09:00:00Z")

        #expect(await health.ids(.sleep).isEmpty)
        #expect(await !health.calls.contains("ask"))
        #expect(try await database.healthStatus().lastRun?.notAllowed == [.sleep])
        #expect(try await database.healthStatus().lastRun?.daysToGo == 0)

        await health.set(access: Dictionary(uniqueKeysWithValues: HealthKind.allCases.map { ($0, .allowed) }))
        _ = await run(health, at: "2026-10-27T10:00:00Z")
        #expect(await health.ids(.sleep).count == 3)
    }

    /// Only with Vesel on screen: Apple's sheet for the kinds a newer Vesel writes, then they're written.
    @Test func kindsNeverAskedAboutAreAskedForOnScreen() async throws {
        let health = FakeHealth(access: [.heartRate: .allowed, .sleep: .notAsked, .steps: .allowed, .restingHeartRate: .allowed, .respiratoryRate: .allowed])
        await health.set(afterAsking: Dictionary(uniqueKeysWithValues: HealthKind.allCases.map { ($0, .allowed) }))

        _ = await run(health, at: "2026-10-27T09:00:00Z", ask: true)

        #expect(await health.calls.first == "ask")
        #expect(await health.ids(.sleep).count == 3)
    }

    @Test func aFailedSaveIsShownAndRetriedNextRun() async throws {
        let health = FakeHealth()
        await health.set(saveError: .failed)

        #expect(await run(health, at: "2026-10-27T09:00:00Z") == .failed)
        #expect(try await database.healthStatus().lastRun?.outcome == .failed)

        await health.set(saveError: nil)
        #expect(await run(health, at: "2026-10-27T10:00:00Z") == .upToDate)
        #expect(await health.ids(.heartRate).count == 4)
    }

    @Test func aCancelledRunStopsBeforeTheNextUnit() async throws {
        let health = FakeHealth()

        let outcome = await run(health, at: "2026-10-27T09:00:00Z") {
            withUnsafeCurrentTask { $0?.cancel() }
            return true
        }

        #expect(outcome == .stopped)
        #expect(await health.calls.isEmpty)
        #expect(try await database.healthStatus().lastRun?.daysToGo == 2)
    }

    @Test func offWritesNothing() async throws {
        try await database.setHealthWrite(false)
        let health = FakeHealth()

        #expect(await run(health, at: "2026-10-27T09:00:00Z") == .off)
        #expect(await health.calls.isEmpty)
        #expect(try await database.healthStatus().lastRun == nil)
    }

    @Test func turningOffStopsARunBeforeTheNextUnit() async throws {
        let health = FakeHealth()
        let checks = Counter()
        let database = database

        let outcome = await writer(health, at: "2026-10-27T09:00:00Z").run(askForNewKinds: false) {
            if checks.next() == 3 { try? await database.setHealthWrite(false) }
            return true
        }

        #expect(outcome == .off)
        #expect(await health.calls == ["save heartRate/2026-10-27", "remove heartRate/2026-10-27"])
        #expect(try await database.healthStatus().lastRun == nil)
    }

    /// 06:02 to 06:32 in Berlin, without heart rate of its own: it takes the 06:05 reading from its day.
    @Test func notAWorkoutRemovesItAndGivesItsReadingBackToTheDay() async throws {
        let start = at("2026-10-27T05:02:00Z")
        let workout = Workout(
            session: "20261027/060200", start: start, end: start.addingTimeInterval(1800), utcOffsetSeconds: 3600, bandSportId: 1, durationSeconds: 1800,
            calories: 250, cardioLoad: nil, cardioLoadRating: nil, trainingLoad: nil, averageHeartRate: nil, maxHeartRate: nil, heartRates: nil,
            fileSize: 1, unreadableFiles: [])
        try await database.save(BandWorkout(workout: workout, files: []), storedAt: at("2026-10-27T08:00:00Z"))
        let health = FakeHealth()
        #expect(await run(health, at: "2026-10-27T09:00:00Z") == .upToDate)
        #expect(await health.ids(.workout) == ["vesel.workout.20261027/060200"])
        #expect(await health.ids(.heartRate).count == 3)

        try await database.setChoice(WorkoutChoice(session: "20261027/060200", sport: nil, hidden: true, chosenAt: at("2026-10-27T09:30:00Z")))
        #expect(await run(health, at: "2026-10-27T10:00:00Z") == .upToDate)

        #expect(await health.ids(.workout).isEmpty)
        #expect(await health.ids(.heartRate).count == 4)
        #expect(await health.calls.contains("remove workout/20261027/060200"))
    }
}

final class Counter: Sendable {
    private let count = Mutex(0)
    func next() -> Int { count.withLock { $0 += 1; return $0 } }
}
