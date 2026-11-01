import Foundation
import GRDB
import Testing
import VeselCore
@testable import VeselStorage

struct FirstWeekObservationTests {
    let berlin = TimeZone(identifier: "Europe/Berlin")!
    let database: AppDatabase

    init() throws {
        database = try AppDatabase.inMemory()
    }

    func day(_ string: String) -> DayKey { DayKey(string)! }

    /// Asleep from `start` (Berlin, UTC+1 or +2) for 8 hours.
    func saveNight(_ night: String, start: String) async throws {
        let begin = at(start)
        try await database.save(
            SleepNight(night: day(night), start: begin, end: begin.addingTimeInterval(8 * 3600), goalMinutes: nil, phases: []), rawJSON: "{}"
        )
    }

    func saveReadings(_ day: String, _ readings: Double) async throws {
        try await database.save(
            ComputedMetric(
                kind: MetricKind.stressReadings, day: self.day(day), hour: nil, value: readings, unit: "",
                explanation: Explanation(method: Stress.method, version: Stress.version, inputs: [], text: ""), computedAt: at("2026-10-25T08:00:00Z")
            ))
    }

    @Test func todayCountsTheNightsAndDaysThatCameIn() async throws {
        for night in ["2026-10-20", "2026-10-21", "2026-10-23", "2026-10-24", "2026-10-25"] {
            try await saveNight(night, start: "\(day(night).adding(days: -1))T21:00:00Z")
        }
        try await database.save(
            NightlyRecharge(night: day("2026-10-22"), recoveryIndicator: 4, recoveryIndicatorSubLevel: 0, meanNightlyRecoveryRMSSD: 40), rawJSON: "{}"
        )
        for (day, readings) in [("2026-10-22", 40.0), ("2026-10-23", 4), ("2026-10-24", 30), ("2026-10-25", 20)] {
            try await saveReadings(day, readings)
        }
        let today = day("2026-10-25")

        let snapshot = try await database.writer.read { try AppDatabase.todaySnapshot($0, day: today, today: today) }

        let week = try #require(snapshot.firstWeek)
        #expect(week.rows.map(\.line) == [.recovery, .sleep, .calm])
        #expect(week.rows[0].cells == [.checked, .checked, .checked, .checked, .checked, .checked, .ahead])
        #expect(week.rows[0].text == "1 more night · Tue")
        #expect(week.rows[1].cells == [.checked, .checked, .missed, .checked, .checked, .checked, .ahead, .ahead])
        #expect(week.rows[2].checked == 2)
        #expect(week.rows[2].missed == 1)
        #expect(week.rows[2].text == "about 12 more days")

        let past = try await database.writer.read { try AppDatabase.todaySnapshot($0, day: self.day("2026-10-24"), today: today) }
        #expect(past.firstWeek == nil)
    }

    @Test func theUsualBedtimeComesFromTheNightsBefore() async throws {
        // Berlin is UTC+2 until 25 Oct, then UTC+1.
        let starts = [
            ("2026-10-20", "2026-10-19T21:05:00Z"), ("2026-10-21", "2026-10-20T21:20:00Z"), ("2026-10-22", "2026-10-21T20:50:00Z"),
            ("2026-10-23", "2026-10-22T22:10:00Z"), ("2026-10-24", "2026-10-23T21:15:00Z"), ("2026-10-25", "2026-10-24T21:00:00Z"),
            ("2026-10-26", "2026-10-25T22:30:00Z"), ("2026-10-27", "2026-10-26T20:00:00Z"),
        ]
        for (night, start) in starts { try await saveNight(night, start: start) }

        var observed = database.observeUsualBedtime(before: day("2026-10-27"), zone: berlin).makeAsyncIterator()
        #expect(try await observed.next()??.text == "23:15")
        var tooFew = database.observeUsualBedtime(before: day("2026-10-26"), zone: berlin).makeAsyncIterator()
        #expect(try await tooFew.next()! == nil)
    }

    @Test func theBusiestSpanIsReadBackForItsDay() async throws {
        let start = at("2026-10-26T12:07:00Z")
        let explanation = Explanation(
            method: "stress", version: 1,
            inputs: [.init(name: "spanStart", value: start.timeIntervalSince1970, unit: "unix s"), .init(name: "spanSeconds", value: 7200, unit: "s")],
            text: "The busiest 2 hours."
        )
        try await database.save(
            ComputedMetric(
                kind: MetricKind.stressBusiestSpan, day: day("2026-10-26"), hour: nil, value: 55, unit: "min", explanation: explanation, computedAt: start
            ))

        var found = database.observeBusiestSpan(day: day("2026-10-26")).makeAsyncIterator()
        let span = try #require(try await found.next()!)
        #expect(span.start == start)
        #expect(span.end == start.addingTimeInterval(7200))
        #expect(span.minutes == 55)
        var other = database.observeBusiestSpan(day: day("2026-10-25")).makeAsyncIterator()
        #expect(try await other.next()! == nil)
    }
}
