import Foundation
import Testing
import VeselCore
@testable import VeselStorage

struct HeartRateObservationTests {
    let night = DayKey("2026-10-26")!
    let berlin = TimeZone(identifier: "Europe/Berlin")!

    func sample(_ iso: String, _ bpm: Int) -> HeartRateSample {
        HeartRateSample(time: at(iso), bpm: bpm, trigger: .timed)
    }

    func first(_ database: AppDatabase) async throws -> [HeartRateSample] {
        for try await value in database.observeNightHeartRates(night) { return value }
        return []
    }

    @Test func readsTheSleepWindowEndsIncludedInOrder() async throws {
        let database = try AppDatabase.inMemory()
        try await database.save(
            SleepNight(night: night, start: at("2026-10-25T21:30:00Z"), end: at("2026-10-26T05:30:00Z"), goalMinutes: nil, phases: []),
            rawJSON: "{}"
        )
        try await database.save(heartRates: [
            sample("2026-10-26T05:30:00Z", 51),
            sample("2026-10-25T21:29:59Z", 70),
            sample("2026-10-26T01:00:00Z", 48),
            sample("2026-10-25T21:30:00Z", 58),
            sample("2026-10-26T05:30:01Z", 66),
        ])
        let bpm = try await first(database).map(\.bpm)
        #expect(bpm == [58, 48, 51])
    }

    @Test func aNightThatIsNotStoredIsEmpty() async throws {
        let database = try AppDatabase.inMemory()
        try await database.save(heartRates: [sample("2026-10-26T01:00:00Z", 48)])
        #expect(try await first(database).isEmpty)
    }

    func periods(_ database: AppDatabase) async throws -> [FiveMinuteMean] {
        for try await value in database.observeHeartRatePeriods(endingOn: night, days: 7, zone: berlin) { return value }
        return []
    }

    @Test func aBurstAveragesPerFiveMinutes() async throws {
        let database = try AppDatabase.inMemory()
        var samples = [sample("2026-10-26T08:00:00Z", 60)]
        let burst = at("2026-10-26T08:05:00Z")
        for second in 0..<60 { samples.append(HeartRateSample(time: burst.addingTimeInterval(Double(second)), bpm: 100, trigger: .timed)) }
        try await database.save(heartRates: samples)
        let found = try await periods(database)
        #expect(found.map(\.mean) == [60, 100])
        #expect(found.map(\.period) == [at("2026-10-26T08:00:00Z"), at("2026-10-26T08:05:00Z")].map { Int64($0.timeIntervalSince1970) / 300 })
    }

    @Test func onlyTheRangeInTheZoneCountsAndEmptyPeriodsAreLeftOut() async throws {
        let database = try AppDatabase.inMemory()
        try await database.save(heartRates: [
            sample("2026-10-19T21:55:00Z", 40),
            sample("2026-10-19T22:00:00Z", 70),
            sample("2026-10-26T22:59:00Z", 90),
            sample("2026-10-26T23:00:00Z", 30),
        ])
        #expect(try await periods(database).map(\.mean) == [70, 90])
    }

    @Test func markingRowsUploadedDoesNotRunItAgain() async throws {
        let database = try AppDatabase.inMemory()
        try await database.save(heartRates: [sample("2026-10-26T08:00:00Z", 60)])
        var values = database.observeHeartRatePeriods(endingOn: night, days: 7, zone: berlin).makeAsyncIterator()
        #expect(try await values.next()?.count == 1)
        let pending = try await database.pendingUploads(.hrSample, limit: 10, now: at("2026-10-27T00:00:00Z"))
        try await database.markUploaded(.hrSample, pending, at: at("2026-10-27T00:00:00Z"))
        try await database.save(heartRates: [sample("2026-10-26T09:00:00Z", 70)])
        #expect(try await values.next()?.count == 2)
    }
}
