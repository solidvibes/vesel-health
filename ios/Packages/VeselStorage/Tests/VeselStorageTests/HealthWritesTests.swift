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

    /// Writes every pending unit as the writer does: read its batch, then mark it at the read's time; at the end, remember
    /// whether Workouts were allowed.
    func writeAll(_ clock: FixedClock, kinds: Set<HealthKind>? = nil) async throws {
        let kinds = kinds ?? all
        for unit in try await database.pendingHealthUnits(kinds: kinds, zone: berlin) {
            let read = try await database.healthBatch(unit, kinds: kinds, clock: clock)
            if read.batch.items.isEmpty, read.last != nil {
                try await database.forgetHealthWrite(unit)
            } else {
                try await database.markHealthWritten(unit, digest: read.batch.digest, version: 1, at: read.snapshot)
            }
        }
        try await database.healthDaysWritten(kinds: kinds, withWorkouts: kinds.contains(.workout))
    }

    @Test func everythingWithDataIsPendingNewestFirstUntilWritten() async throws {
        try await heartRates([60, 62], readAt: "2026-10-27T10:00:00Z")
        try await steps(readAt: "2026-10-27T10:00:00Z")
        try await sleep()
        try await restingHeartRate(52, computedAt: "2026-10-27T10:00:00Z")
        try await database.save([BandPayload.empty(day: DayKey("2026-10-26")!, kind: .heartRate, utcOffsetSeconds: 3600)], fetchedAt: at("2026-10-27T10:00:00Z"))
        try await heartRatesOn("2026-10-20", readAt: "2026-10-21T10:00:00Z")

        let pending = try await database.pendingHealthUnits(kinds: all, zone: berlin)

        #expect(
            pending.map(\.id) == [
                "heartRate/2026-10-27", "restingHeartRate/2026-10-27", "sleep/2026-10-27", "steps/2026-10-27", "heartRate/2026-10-20",
            ])
        #expect(try await database.pendingHealthUnits(kinds: [.sleep], zone: berlin).map(\.id) == ["sleep/2026-10-27"])

        try await writeAll(clock("2026-10-27T11:00:00Z"))
        #expect(try await database.pendingHealthUnits(kinds: all, zone: berlin).isEmpty)
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
        #expect(try await database.pendingHealthUnits(kinds: all, zone: berlin).isEmpty)

        try await heartRates([60, 64], readAt: "2026-10-27T11:00:00Z")
        #expect(try await database.pendingHealthUnits(kinds: all, zone: berlin).map(\.id) == ["heartRate/2026-10-27"])
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

        #expect(try await database.pendingHealthUnits(kinds: all, zone: berlin).map(\.id) == ["sleep/2026-10-27"])
    }

    /// The metric went (Polar withdrew it): the night is pending with nothing to write, and forgetting it ends that.
    @Test func aUnitWhoseDataWentIsPendingWithAnEmptyBatch() async throws {
        try await restingHeartRate(52, computedAt: "2026-10-27T10:00:00Z")
        try await writeAll(clock("2026-10-27T11:00:00Z"))

        try await database.writer.write { try $0.execute(sql: "DELETE FROM computed_metric") }

        let unit = HealthUnit(kind: .restingHeartRate, day: night)
        #expect(try await database.pendingHealthUnits(kinds: all, zone: berlin) == [unit])
        let read = try await database.healthBatch(unit, kinds: all, clock: clock("2026-10-27T12:00:00Z"))
        #expect(read.batch.items.isEmpty)
        #expect(read.last != nil)
        try await database.forgetHealthWrite(unit)
        #expect(try await database.pendingHealthUnits(kinds: all, zone: berlin).isEmpty)
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
        #expect(try await database.pendingHealthUnits(kinds: all, zone: berlin).isEmpty)

        try await database.setHealthWrite(true)
        #expect(try await database.healthStatus() == HealthStatus(isOn: true, lastRun: nil))
        #expect(try await database.pendingHealthUnits(kinds: all, zone: berlin).map(\.id) == ["heartRate/2026-10-27"])
    }

    @Test func theStatusIsOffUntilTurnedOn() async throws {
        var updates = try await database.observeHealthStatus().makeAsyncIterator()
        #expect(try await updates.next() == HealthStatus(isOn: false, lastRun: nil))
        try await database.setHealthWrite(true)
        #expect(try await updates.next() == HealthStatus(isOn: true, lastRun: nil))
    }

    // MARK: Workouts and energy

    func heartRates(on day: String, _ times: [String], readAt: String) async throws {
        let samples = times.enumerated().map { #"{"hr":\#(60 + $0 * 2),"time":"\#($1)","triggerType":"TIMED"}"# }
        let payload = BandPayload(
            day: DayKey(day)!, kind: .heartRate, json: #"{"date":"\#(day)","samples":[\#(samples.joined(separator: ","))]}"#,
            utcOffsetSeconds: 3600, sampleCount: times.count)
        try await database.save([payload], fetchedAt: at(readAt))
    }

    /// BMR 1728 kcal, 600 kcal of activity.
    func summary(_ day: String, readAt: String) async throws {
        let payload = BandPayload(
            day: DayKey(day)!, kind: .dailySummary,
            json: #"{"date":"\#(day)","steps":5000,"activeDurationSeconds":3000,"calories":{"bmr":1728,"activity":600,"total":2328}}"#,
            utcOffsetSeconds: 3600, sampleCount: 1)
        try await database.save([payload], fetchedAt: at(readAt))
    }

    /// 300 kcal over 30 minutes, without heart rate of its own: its resting share is 1728 × 1800 ÷ 86 400 = 36 kcal.
    func workout(_ session: String, start: String, storedAt: String) async throws {
        let begin = at(start)
        let workout = Workout(
            session: session, start: begin, end: begin.addingTimeInterval(1800), utcOffsetSeconds: 3600, bandSportId: 1, durationSeconds: 1800,
            calories: 300, cardioLoad: nil, cardioLoadRating: nil, trainingLoad: nil, averageHeartRate: nil, maxHeartRate: nil, heartRates: nil,
            fileSize: 1, unreadableFiles: [])
        try await database.save(BandWorkout(workout: workout, files: []), storedAt: at(storedAt))
    }

    func items(_ id: String, kinds: Set<HealthKind>? = nil) async throws -> [HealthItem] {
        try await database.healthBatch(HealthUnit(id: id)!, kinds: kinds ?? all, clock: clock("2026-10-27T13:00:00Z")).batch.items
    }

    /// 09:00, 09:01 and 09:02 in Berlin; the workout from 09:00:30 to 09:30:30 takes the last two.
    func dayWithAWorkout() async throws {
        try await heartRates(on: "2026-10-27", ["09:00:00", "09:01:00", "09:02:00"], readAt: "2026-10-27T10:00:00Z")
        try await summary("2026-10-27", readAt: "2026-10-27T10:00:00Z")
        try await workout("20261027/090030", start: "2026-10-27T08:00:30Z", storedAt: "2026-10-27T10:00:00Z")
    }

    @Test func aWorkoutTakesItsReadingsAndEnergyFromItsDay() async throws {
        try await dayWithAWorkout()

        #expect(try await items("heartRate/2026-10-27").map(\.value) == [.quantity(60, .bpm)])
        let energy = try await items("energy/2026-10-27")
        #expect(energy.map(\.syncId) == ["vesel.activeEnergy.2026-10-27", "vesel.restingEnergy.2026-10-27"])
        #expect(energy.first?.value == .quantity(336, .kcal))
        #expect(energy.first?.end == at("2026-10-27T10:00:00Z"))
        let workout = try #require(try await items("workout/20261027/090030").first)
        guard case .workout(let saved) = workout.value else { Issue.record("not a workout"); return }
        #expect(saved.activity == .running)
        #expect(saved.samples.map(\.value) == [.quantity(264, .kcal), .quantity(62, .bpm), .quantity(64, .bpm)])
    }

    @Test func hidingAWorkoutMakesItAndItsDaysPending() async throws {
        try await dayWithAWorkout()
        try await writeAll(clock("2026-10-27T11:00:00Z"))
        #expect(try await database.pendingHealthUnits(kinds: all, zone: berlin).isEmpty)

        try await database.setChoice(WorkoutChoice(session: "20261027/090030", sport: nil, hidden: true, chosenAt: at("2026-10-27T12:00:00Z")))

        #expect(
            Set(try await database.pendingHealthUnits(kinds: all, zone: berlin).map(\.id))
                == ["workout/20261027/090030", "heartRate/2026-10-27", "energy/2026-10-27"])
        #expect(try await items("workout/20261027/090030").isEmpty)
        #expect(try await items("heartRate/2026-10-27").count == 3)
        #expect(try await items("energy/2026-10-27").first?.value == .quantity(600, .kcal))
    }

    @Test func allowingWorkoutsLaterMakesTheHeartRateAndEnergyDaysPending() async throws {
        try await dayWithAWorkout()
        let withoutWorkouts = all.subtracting([.workout])
        try await writeAll(clock("2026-10-27T11:00:00Z"), kinds: withoutWorkouts)
        #expect(try await database.pendingHealthUnits(kinds: withoutWorkouts, zone: berlin).isEmpty)
        #expect(try await items("energy/2026-10-27", kinds: withoutWorkouts).first?.value == .quantity(600, .kcal))

        #expect(
            Set(try await database.pendingHealthUnits(kinds: all, zone: berlin).map(\.id))
                == ["workout/20261027/090030", "heartRate/2026-10-27", "energy/2026-10-27"])

        try await writeAll(clock("2026-10-27T12:00:00Z"))
        #expect(try await database.pendingHealthUnits(kinds: all, zone: berlin).isEmpty)
    }

    /// 23:40 to 00:10 in Berlin: its readings leave both days; its energy comes off the day it started.
    @Test func aWorkoutAcrossMidnightLeavesBothDaysReadingsAndTheFirstDaysEnergy() async throws {
        try await heartRates(on: "2026-10-27", ["23:30:00", "23:50:00"], readAt: "2026-10-28T10:00:00Z")
        try await heartRates(on: "2026-10-28", ["00:05:00", "00:30:00"], readAt: "2026-10-28T10:00:00Z")
        try await summary("2026-10-27", readAt: "2026-10-28T10:00:00Z")
        try await summary("2026-10-28", readAt: "2026-10-28T10:00:00Z")
        try await workout("20261027/234000", start: "2026-10-27T22:40:00Z", storedAt: "2026-10-28T10:00:00Z")

        #expect(try await items("heartRate/2026-10-27").map(\.start) == [at("2026-10-27T22:30:00Z")])
        #expect(try await items("heartRate/2026-10-28").map(\.start) == [at("2026-10-27T23:30:00Z")])
        #expect(try await items("energy/2026-10-27").first?.value == .quantity(336, .kcal))
        #expect(try await items("energy/2026-10-28").first?.value == .quantity(600, .kcal))

        try await writeAll(clock("2026-10-28T11:00:00Z"))
        try await heartRates(on: "2026-10-28", ["00:05:00", "00:08:00", "00:30:00"], readAt: "2026-10-28T12:00:00Z")
        #expect(try await database.pendingHealthUnits(kinds: all, zone: berlin).map(\.id).contains("workout/20261027/234000"))
    }
}
