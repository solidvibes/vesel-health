import Foundation
import Testing
import VeselCore
@testable import VeselStorage

struct StepsObservationTests {
    let database: AppDatabase
    let today = DayKey("2026-10-28")!

    init() async throws {
        database = try AppDatabase.inMemory()
    }

    func read(_ day: DayKey, steps: Int, at fetchedAt: String) async throws {
        let payload = BandPayload(
            day: day, kind: .dailySummary,
            json: "{\"date\":\"\(day)\",\"steps\":\(steps),\"activeDurationSeconds\":3000,\"calories\":{\"bmr\":1700,\"activity\":300,\"total\":2000}}",
            utcOffsetSeconds: 0, sampleCount: 1
        )
        try await database.save([payload], fetchedAt: at(fetchedAt))
    }

    func snapshot(_ day: DayKey) async throws -> TodaySnapshot {
        try await database.writer.read { try AppDatabase.todaySnapshot($0, day: day, today: self.today) }
    }

    @Test func todayShowsTodaysStepsAndWhenTheBandWasLastReadForThem() async throws {
        try await read(today, steps: 4100, at: "2026-10-28T10:05:00Z")
        try await read(today, steps: 6240, at: "2026-10-28T14:32:00Z")
        let found = try await snapshot(today)
        #expect(found.steps == 6240)
        #expect(found.stepsReadAt == at("2026-10-28T14:32:00Z"))
    }

    @Test func aPastDayHasItsOwnStepsAndNoReadTime() async throws {
        let yesterday = today.adding(days: -1)
        try await read(yesterday, steps: 8850, at: "2026-10-28T06:00:00Z")
        try await read(today, steps: 6240, at: "2026-10-28T14:32:00Z")
        let found = try await snapshot(yesterday)
        #expect(found.steps == 8850)
        #expect(found.stepsReadAt == nil)
    }

    @Test func noStepsRowOrZeroStepsMeansNoSteps() async throws {
        #expect(try await snapshot(today).steps == nil)
        try await read(today, steps: 0, at: "2026-10-28T08:00:00Z")
        let found = try await snapshot(today)
        #expect(found.steps == nil)
        #expect(found.stepsReadAt == nil)
    }

    @Test func bodyGetsOneStepsPointPerDayWithStepsAndWhenItWasRead() async throws {
        try await read(today.adding(days: -2), steps: 7000, at: "2026-10-26T20:00:00Z")
        try await read(today.adding(days: -1), steps: 0, at: "2026-10-27T20:00:00Z")
        try await read(today, steps: 6240, at: "2026-10-28T14:32:00Z")
        let found = try await database.writer.read { try AppDatabase.trends($0, today: self.today) }
        let series = try #require(found.series[MetricKind.steps])
        #expect(series.map(\.day) == [today.adding(days: -2), today])
        #expect(series.map(\.value) == [7000, 6240])
        #expect(series.last?.computedAt == at("2026-10-28T14:32:00Z"))
    }

    @Test func stepsReachBackAsFarAsTheOtherTrends() async throws {
        let oldest = today.adding(days: -(TrendsSnapshot.days - 1))
        try await read(oldest, steps: 5000, at: "2026-07-01T20:00:00Z")
        try await read(oldest.adding(days: -1), steps: 5000, at: "2026-07-01T20:00:00Z")
        let found = try await database.writer.read { try AppDatabase.trends($0, today: self.today) }
        #expect(found.series[MetricKind.steps]?.map(\.day) == [oldest])
    }
}
