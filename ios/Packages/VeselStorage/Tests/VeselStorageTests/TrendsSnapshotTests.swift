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

    func snapshot(endingOn day: DayKey, kinds: [String] = TrendsSnapshot.kinds) async throws -> TrendsSnapshot {
        try await database.writer.read { try AppDatabase.trends($0, today: day, kinds: kinds) }
    }

    func saveNight(_ night: String, _ start: String, _ end: String) async throws {
        try await database.save(SleepNight(night: DayKey(night)!, start: at(start), end: at(end), goalMinutes: nil, phases: []), rawJSON: "{}")
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

    @Test func onlyTheKindsAskedForAreRead() async throws {
        let today = DayKey("2026-10-27")!
        try await store(MetricKind.sleepInBed, on: today)
        try await store(Contributor.hrv.kind, on: today)
        let found = try await snapshot(endingOn: today, kinds: [MetricKind.sleepInBed])
        #expect(Set(found.series.keys) == [MetricKind.sleepInBed])
        #expect(found.series[MetricKind.sleepInBed]?.map(\.day) == [today])
    }

    @Test func stepsAreReadOnlyWhenAsked() async throws {
        let today = DayKey("2026-10-27")!
        #expect(try await snapshot(endingOn: today).series[MetricKind.steps] != nil)
        #expect(try await snapshot(endingOn: today, kinds: [Contributor.hrv.kind]).series[MetricKind.steps] == nil)
    }

    @Test func sleepStagesAreTheWindowsDeepLightAndRemMinutes() async throws {
        let today = DayKey("2026-10-27")!
        for (offset, kinds) in [(0, [SleepState.deep, .light, .rem, .wake]), (-1, [.deep]), (-3, [.deep, .light, .rem])] {
            for state in kinds {
                try await database.save(
                    ComputedMetric(
                        kind: MetricKind.sleepStage(state), day: today.adding(days: offset), hour: nil, value: state == .wake ? 99 : 60, unit: "min",
                        explanation: Explanation(method: "test", version: 1, inputs: [], text: ""), computedAt: at("2026-10-27T12:00:00Z")
                    ))
            }
        }
        var found: [NightStages] = []
        for try await value in database.observeSleepStages(endingOn: today, days: 3) {
            found = value
            break
        }
        #expect(found == [NightStages(night: today.adding(days: -1), deep: 60, light: 0, rem: 0), NightStages(night: today, deep: 60, light: 60, rem: 60)])
    }

    @Test func sleepTimesAreTheWindowsNightsOldestFirst() async throws {
        try await saveNight("2026-10-27", "2026-10-26T22:00:00Z", "2026-10-27T06:00:00Z")
        try await saveNight("2026-10-25", "2026-10-24T22:30:00Z", "2026-10-25T06:30:00Z")
        try await saveNight("2026-10-20", "2026-10-19T22:00:00Z", "2026-10-20T06:00:00Z")
        var found: [SleepNightTimes] = []
        for try await value in database.observeSleepTimes(endingOn: DayKey("2026-10-27")!, days: 7) {
            found = value
            break
        }
        #expect(found.map(\.night) == [DayKey("2026-10-25")!, DayKey("2026-10-27")!])
        #expect(found.first?.start == at("2026-10-24T22:30:00Z"))
        #expect(found.last?.end == at("2026-10-27T06:00:00Z"))
    }
}
