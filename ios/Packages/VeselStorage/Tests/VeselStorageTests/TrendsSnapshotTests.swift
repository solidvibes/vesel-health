import Foundation
import Testing
import VeselCore
@testable import VeselStorage

struct TrendsSnapshotTests {
    let database: AppDatabase

    init() async throws {
        database = try AppDatabase.inMemory()
    }

    func store(_ kind: String, on day: DayKey) async throws {
        try await database.save(
            ComputedMetric(
                kind: kind, day: day, hour: nil, value: 34.6, unit: "°C",
                explanation: Explanation(method: "test", version: 1, inputs: [], text: ""), computedAt: at("2026-10-27T12:00:00Z")
            ))
    }

    func snapshot(endingOn day: DayKey) async throws -> TrendsSnapshot {
        try await database.writer.read { try AppDatabase.trends($0, today: day) }
    }

    @Test func skinTemperatureIsOneOfTheTrendedNumbers() async throws {
        let today = DayKey("2026-10-27")!
        try await store(Contributor.skinTemperature.kind, on: today)
        let found = try await snapshot(endingOn: today)
        #expect(found.series[Contributor.skinTemperature.kind]?.map(\.day) == [today])
    }

    @Test func itReachesBackThreeMonthsAndTheFourWeeksBeforeThem() async throws {
        let today = DayKey("2026-10-27")!
        let oldest = today.adding(days: -(TrendsSnapshot.days - 1))
        try await store(MetricKind.sleepLowestHeartRate, on: oldest)
        try await store(MetricKind.sleepLowestHeartRate, on: oldest.adding(days: -1))
        let found = try await snapshot(endingOn: today)
        #expect(TrendsSnapshot.days == 118)
        #expect(found.series[MetricKind.sleepLowestHeartRate]?.map(\.day) == [oldest])
    }
}
