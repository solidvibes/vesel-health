import Foundation
import Testing
import VeselCore
@testable import VeselStorage

struct SleepSpansObservationTests {
    let berlin = TimeZone(identifier: "Europe/Berlin")!

    func save(_ database: AppDatabase, night: String, _ start: String, _ end: String) async throws {
        try await database.save(SleepNight(night: DayKey(night)!, start: at(start), end: at(end), goalMinutes: nil, phases: []), rawJSON: "{}")
    }

    func spans(_ database: AppDatabase, _ day: String) async throws -> [ClosedRange<Date>] {
        for try await value in database.observeSleepSpans(day: DayKey(day)!, zone: berlin) { return value }
        return []
    }

    @Test func theNightStoredAsTheDayIsClippedToItsMorning() async throws {
        let database = try AppDatabase.inMemory()
        try await save(database, night: "2026-10-26", "2026-10-25T22:30:00Z", "2026-10-26T05:30:00Z")
        // Berlin is UTC+1 on 26 Oct: the day starts 23:00Z on the 25th, so the night began 30 minutes before it.
        let found = try await spans(database, "2026-10-26")
        #expect(found == [at("2026-10-25T23:00:00Z")...at("2026-10-26T05:30:00Z")])
    }

    @Test func theEveningSleepBeforeMidnightBelongsToTheNextNight() async throws {
        let database = try AppDatabase.inMemory()
        try await save(database, night: "2026-10-27", "2026-10-26T21:00:00Z", "2026-10-27T05:00:00Z")
        // The 26th ends at 23:00Z: its evening share is 21:00Z to 23:00Z.
        let found = try await spans(database, "2026-10-26")
        #expect(found == [at("2026-10-26T21:00:00Z")...at("2026-10-26T23:00:00Z")])
    }

    @Test func bothNightsOfADayComeOldestFirst() async throws {
        let database = try AppDatabase.inMemory()
        try await save(database, night: "2026-10-27", "2026-10-26T21:00:00Z", "2026-10-27T05:00:00Z")
        try await save(database, night: "2026-10-26", "2026-10-25T23:00:00Z", "2026-10-26T05:30:00Z")
        let found = try await spans(database, "2026-10-26")
        #expect(found == [at("2026-10-25T23:00:00Z")...at("2026-10-26T05:30:00Z"), at("2026-10-26T21:00:00Z")...at("2026-10-26T23:00:00Z")])
    }

    @Test func noNightsGiveNoSpans() async throws {
        let database = try AppDatabase.inMemory()
        try await save(database, night: "2026-10-20", "2026-10-19T21:00:00Z", "2026-10-20T05:00:00Z")
        #expect(try await spans(database, "2026-10-26").isEmpty)
    }

    @Test func aNightThatEndsAtMidnightSharpLeavesNothingInTheNextDay() async throws {
        let database = try AppDatabase.inMemory()
        try await save(database, night: "2026-10-26", "2026-10-25T20:00:00Z", "2026-10-25T23:00:00Z")
        #expect(try await spans(database, "2026-10-26").isEmpty)
    }

    @Test func theTwentyFiveHourDayKeepsAllItsSleep() async throws {
        // Berlin leaves summer time on 25 Oct 2026: the day runs from 22:00Z on the 24th to 23:00Z on the 25th.
        let database = try AppDatabase.inMemory()
        try await save(database, night: "2026-10-25", "2026-10-24T21:00:00Z", "2026-10-25T04:00:00Z")
        try await save(database, night: "2026-10-26", "2026-10-25T21:30:00Z", "2026-10-26T05:30:00Z")
        let found = try await spans(database, "2026-10-25")
        #expect(found == [at("2026-10-24T22:00:00Z")...at("2026-10-25T04:00:00Z"), at("2026-10-25T21:30:00Z")...at("2026-10-25T23:00:00Z")])
    }
}
