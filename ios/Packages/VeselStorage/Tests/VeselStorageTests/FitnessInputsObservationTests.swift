import Foundation
import Testing
import VeselCore
@testable import VeselStorage

struct FitnessInputsObservationTests {
    let today = DayKey("2026-10-02")!
    let profile = Profile(birthYear: 1986, sex: .male, heightCm: 180, weightKg: 81, sleepGoalMinutes: 480)

    func summary(_ day: String, classes: String? = "{\"nonWear\":600,\"continuousModerate\":1500,\"intermittentVigorous\":600}") -> BandPayload {
        let body = classes.map { ",\"activityClassSeconds\":\($0)" } ?? ""
        return BandPayload(
            day: DayKey(day)!, kind: .dailySummary,
            json: "{\"date\":\"\(day)\",\"steps\":1000,\"activeDurationSeconds\":3000,\"calories\":{\"bmr\":1700,\"activity\":300,\"total\":2000}\(body)}",
            utcOffsetSeconds: 7200, sampleCount: 1
        )
    }

    func resting(_ day: String, _ bpm: Double) -> ComputedMetric {
        ComputedMetric(
            kind: FitnessAge.restingHeartRateKind, day: DayKey(day)!, hour: nil, value: bpm, unit: "bpm",
            explanation: Explanation(method: "recovery", version: 1, inputs: [], text: ""), computedAt: at("2026-10-01T06:00:00Z")
        )
    }

    func first(_ database: AppDatabase) async throws -> FitnessInputs? {
        for try await value in database.observeFitnessInputs(today: today) { return value }
        return nil
    }

    @Test func readsOnlyThePreviousMonthsWindow() async throws {
        let database = try AppDatabase.inMemory()
        try await database.save(profile)
        try await database.save(
            [summary("2026-09-02"), summary("2026-09-03"), summary("2026-09-30"), summary("2026-10-01")], fetchedAt: at("2026-10-02T06:00:00Z"))
        for (day, bpm) in [("2026-09-02", 70.0), ("2026-09-03", 55), ("2026-09-30", 57), ("2026-10-01", 80)] {
            try await database.save(resting(day, bpm))
        }
        let found = try #require(try await first(database))
        #expect(found.profile == profile)
        #expect(found.restingHeartRates.sorted() == [55, 57])
        #expect(found.days.map(\.day) == [DayKey("2026-09-03")!, DayKey("2026-09-30")!])
        #expect(found.days[0].classSeconds == ["nonWear": 600, "continuousModerate": 1500, "intermittentVigorous": 600])
    }

    @Test func aSummaryWithoutClassSecondsIsLeftOut() async throws {
        let database = try AppDatabase.inMemory()
        try await database.save(profile)
        try await database.save([summary("2026-09-10", classes: nil), summary("2026-09-11")], fetchedAt: at("2026-10-02T06:00:00Z"))
        let found = try #require(try await first(database))
        #expect(found.days.map(\.day) == [DayKey("2026-09-11")!])
    }

    @Test func markingRowsUploadedDoesNotRunItAgain() async throws {
        let database = try AppDatabase.inMemory()
        try await database.save(profile)
        try await database.save([summary("2026-09-10")], fetchedAt: at("2026-10-02T06:00:00Z"))
        try await database.save(resting("2026-09-10", 55))
        var values = database.observeFitnessInputs(today: today).makeAsyncIterator()
        #expect(try await values.next()??.restingHeartRates.count == 1)
        let now = at("2026-10-27T00:00:00Z")
        for table in [UploadTable.profile, .rawExport, .computedMetric] {
            try await database.markUploaded(table, try await database.pendingUploads(table, limit: 10, now: now), at: now)
        }
        try await database.save(resting("2026-09-11", 57))
        #expect(try await values.next()??.restingHeartRates.count == 2)
    }

    @Test func noProfileIsNil() async throws {
        let database = try AppDatabase.inMemory()
        #expect(try await first(database) == nil)
    }

    @Test func theProfileComesWithItsWaistAndOutsideVO2max() async throws {
        let database = try AppDatabase.inMemory()
        var withWaist = profile
        withWaist.waistCm = 88
        withWaist.measuredVO2max = 47
        try await database.save(withWaist)
        let found = try #require(try await first(database))
        #expect(found.profile == withWaist)
    }
}
