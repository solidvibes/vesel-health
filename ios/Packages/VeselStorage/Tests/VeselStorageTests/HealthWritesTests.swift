import Foundation
import GRDB
import Testing
import VeselCore
@testable import VeselStorage

/// What's pending for Apple Health, from the bookkeeping and the times readings were stored. Berlin is UTC+1 on 2026-10-27.
struct HealthWritesTests {
    let berlin = TimeZone(identifier: "Europe/Berlin")!
    let database: AppDatabase
    let all = Set(HealthKind.allCases)
    let night = DayKey("2026-10-27")!

    init() async throws {
        database = try AppDatabase.inMemory()
    }

    func clock(_ iso: String) -> FixedClock {
        FixedClock(now: at(iso), timeZone: berlin)
    }

    func heartRates(_ bpm: [Int], readAt: String) async throws {
        let samples = bpm.enumerated().map { #"{"hr":\#($1),"time":"09:0\#($0):00","triggerType":"TIMED"}"# }
        let payload = BandPayload(
            day: night, kind: .heartRate, json: #"{"date":"2026-10-27","samples":[\#(samples.joined(separator: ","))]}"#, utcOffsetSeconds: 3600,
            sampleCount: bpm.count)
        try await database.save([payload], fetchedAt: at(readAt))
    }

    func steps(readAt: String) async throws {
        let payload = BandPayload(
            day: night, kind: .activitySamples, json: #"{"date":"2026-10-27","samples":[{"time":"2026-10-27T08:10:00+01:00","steps":40}]}"#,
            utcOffsetSeconds: 3600, sampleCount: 1)
        try await database.save([payload], fetchedAt: at(readAt))
    }

    func restingHeartRate(_ bpm: Double, computedAt: String) async throws {
        try await database.save(
            ComputedMetric(
                kind: Contributor.restingHeartRate.kind, day: night, hour: nil, value: bpm, unit: "bpm",
                explanation: Explanation(method: RecoveryContributors.method, version: RecoveryContributors.version, inputs: [], text: ""),
                computedAt: at(computedAt)))
    }

    func sleep() async throws {
        let phases = [SleepPhase(secondsFromStart: 0, state: .light), SleepPhase(secondsFromStart: 3600, state: .deep)]
        try await database.save(
            SleepNight(night: night, start: at("2026-10-26T22:00:00Z"), end: at("2026-10-27T06:00:00Z"), goalMinutes: 480, phases: phases), rawJSON: "{}")
    }

    /// Writes every pending unit as the writer does: read its batch, then mark it at the read's time.
    func writeAll(_ clock: FixedClock) async throws {
        for unit in try await database.pendingHealthUnits(kinds: all) {
            let read = try await database.healthBatch(unit, kinds: all, clock: clock)
            if read.batch.items.isEmpty {
                try await database.forgetHealthWrite(unit)
            } else {
                try await database.markHealthWritten(unit, digest: read.batch.digest, version: 1, at: read.snapshot)
            }
        }
    }

    @Test func everythingWithDataIsPendingNewestFirstUntilWritten() async throws {
        try await heartRates([60, 62], readAt: "2026-10-27T10:00:00Z")
        try await steps(readAt: "2026-10-27T10:00:00Z")
        try await sleep()
        try await restingHeartRate(52, computedAt: "2026-10-27T10:00:00Z")
        try await database.save([BandPayload.empty(day: DayKey("2026-10-26")!, kind: .heartRate, utcOffsetSeconds: 3600)], fetchedAt: at("2026-10-27T10:00:00Z"))
        try await heartRatesOn("2026-10-20", readAt: "2026-10-21T10:00:00Z")

        let pending = try await database.pendingHealthUnits(kinds: all)

        #expect(
            pending.map(\.id) == [
                "heartRate/2026-10-27", "restingHeartRate/2026-10-27", "sleep/2026-10-27", "steps/2026-10-27", "heartRate/2026-10-20",
            ])
        #expect(try await database.pendingHealthUnits(kinds: [.sleep]).map(\.id) == ["sleep/2026-10-27"])

        try await writeAll(clock("2026-10-27T11:00:00Z"))
        #expect(try await database.pendingHealthUnits(kinds: all).isEmpty)
    }

    func heartRatesOn(_ day: String, readAt: String) async throws {
        let payload = BandPayload(
            day: DayKey(day)!, kind: .heartRate, json: #"{"date":"\#(day)","samples":[{"hr":58,"time":"12:00:00","triggerType":"TIMED"}]}"#,
            utcOffsetSeconds: 7200, sampleCount: 1)
        try await database.save([payload], fetchedAt: at(readAt))
    }

    @Test func aBatchHoldsTheUnitsItemsAndItsReadTime() async throws {
        try await heartRates([60, 62], readAt: "2026-10-27T10:00:00Z")
        try await sleep()
        try await restingHeartRate(52, computedAt: "2026-10-27T10:00:00Z")
        let clock = clock("2026-10-27T11:00:00Z")

        let heart = try await database.healthBatch(HealthUnit(kind: .heartRate, day: night), kinds: all, clock: clock)
        let resting = try await database.healthBatch(HealthUnit(kind: .restingHeartRate, day: night), kinds: all, clock: clock)

        #expect(heart.batch.items.map(\.value) == [.quantity(60, .bpm), .quantity(62, .bpm)])
        #expect(heart.batch.items.first?.start == at("2026-10-27T08:00:00Z"))
        #expect(heart.snapshot == at("2026-10-27T11:00:00Z"))
        #expect(heart.last == nil)
        #expect(resting.batch.items == [HealthMapping.restingHeartRate(night: night, bpm: 52, sleep: try await database.sleepNight(night), utcOffsetSeconds: 3600)])
    }

    /// A read stores its rows with the time it started. One that started before the write's read is seen; one after makes the day pending.
    @Test func onlyAReadAfterTheWriteMakesTheDayPendingAgain() async throws {
        try await heartRates([60], readAt: "2026-10-27T10:00:00Z")
        try await writeAll(clock("2026-10-27T11:00:00Z"))

        try await heartRates([60, 64], readAt: "2026-10-27T10:30:00Z")
        #expect(try await database.pendingHealthUnits(kinds: all).isEmpty)

        try await heartRates([60, 64], readAt: "2026-10-27T11:00:00Z")
        #expect(try await database.pendingHealthUnits(kinds: all).map(\.id) == ["heartRate/2026-10-27"])
    }

    @Test func aWrittenUnitRemembersItsFingerprintAndVersion() async throws {
        try await heartRates([60], readAt: "2026-10-27T10:00:00Z")
        let unit = HealthUnit(kind: .heartRate, day: night)
        let read = try await database.healthBatch(unit, kinds: all, clock: clock("2026-10-27T11:00:00Z"))
        try await database.markHealthWritten(unit, digest: read.batch.digest, version: 1_793_000_000_000, at: read.snapshot)

        let again = try await database.healthBatch(unit, kinds: all, clock: clock("2026-10-27T12:00:00Z"))

        #expect(again.last == HealthWritten(digest: read.batch.digest, syncVersion: 1_793_000_000_000))
        #expect(again.batch.digest == read.batch.digest)
    }

    @Test func aNewMappingVersionMakesTheKindPending() async throws {
        try await sleep()
        try await writeAll(clock("2026-10-27T11:00:00Z"))

        try await database.writer.write { try $0.execute(sql: "UPDATE health_write SET mapping_version = 0") }

        #expect(try await database.pendingHealthUnits(kinds: all).map(\.id) == ["sleep/2026-10-27"])
    }

    /// The metric went (Polar withdrew it): the night is pending with nothing to write, and forgetting it ends that.
    @Test func aUnitWhoseDataWentIsPendingWithAnEmptyBatch() async throws {
        try await restingHeartRate(52, computedAt: "2026-10-27T10:00:00Z")
        try await writeAll(clock("2026-10-27T11:00:00Z"))

        try await database.writer.write { try $0.execute(sql: "DELETE FROM computed_metric") }

        let unit = HealthUnit(kind: .restingHeartRate, day: night)
        #expect(try await database.pendingHealthUnits(kinds: all) == [unit])
        let read = try await database.healthBatch(unit, kinds: all, clock: clock("2026-10-27T12:00:00Z"))
        #expect(read.batch.items.isEmpty)
        #expect(read.last != nil)
        try await database.forgetHealthWrite(unit)
        #expect(try await database.pendingHealthUnits(kinds: all).isEmpty)
    }

    @Test func turningOnForgetsEveryWriteAndTheLastRun() async throws {
        try await heartRates([60], readAt: "2026-10-27T10:00:00Z")
        try await database.setHealthWrite(true)
        try await writeAll(clock("2026-10-27T11:00:00Z"))
        let run = HealthRun(at: at("2026-10-27T11:00:00Z"), outcome: .written, daysToGo: 0, notAllowed: [.sleep], wroteAny: true)
        try await database.saveHealthRun(run)
        #expect(try await database.healthStatus() == HealthStatus(isOn: true, lastRun: run))

        try await database.setHealthWrite(false)
        #expect(try await database.healthStatus() == HealthStatus(isOn: false, lastRun: run))
        #expect(try await database.pendingHealthUnits(kinds: all).isEmpty)

        try await database.setHealthWrite(true)
        #expect(try await database.healthStatus() == HealthStatus(isOn: true, lastRun: nil))
        #expect(try await database.pendingHealthUnits(kinds: all).map(\.id) == ["heartRate/2026-10-27"])
    }

    @Test func theStatusIsOffUntilTurnedOn() async throws {
        var updates = try await database.observeHealthStatus().makeAsyncIterator()
        #expect(try await updates.next() == HealthStatus(isOn: false, lastRun: nil))
        try await database.setHealthWrite(true)
        #expect(try await updates.next() == HealthStatus(isOn: true, lastRun: nil))
    }
}
