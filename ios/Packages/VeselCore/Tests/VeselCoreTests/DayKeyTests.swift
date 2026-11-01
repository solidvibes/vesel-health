import Foundation
import Testing
import VeselCore

struct DayKeyTests {
    let berlin = TimeZone(identifier: "Europe/Berlin")!
    let newYork = TimeZone(identifier: "America/New_York")!
    let utc = TimeZone(identifier: "UTC")!

    func date(_ iso: String) -> Date {
        try! Date(iso, strategy: .iso8601)
    }

    @Test func writesReadsAndCodesTheString() throws {
        let key = DayKey(year: 2026, month: 3, day: 7)
        #expect(key.description == "2026-03-07")
        #expect(DayKey("2026-03-07") == key)
        #expect(DayKey("2026-13-01") == nil)
        #expect(DayKey("yesterday") == nil)
        let data = try JSONEncoder().encode([key])
        #expect(String(decoding: data, as: UTF8.self) == "[\"2026-03-07\"]")
        #expect(try JSONDecoder().decode([DayKey].self, from: data) == [key])
    }

    @Test func keysANightByTheDateItEndsOn() {
        let end = date("2026-10-27T06:10:00Z")
        #expect(DayKey.night(endingAt: end, in: berlin) == DayKey(year: 2026, month: 10, day: 27))
    }

    @Test func splitsAtLocalMidnightInEachZone() {
        #expect(DayKey(date("2026-10-26T22:59:59Z"), in: berlin) == DayKey(year: 2026, month: 10, day: 26))
        #expect(DayKey(date("2026-10-26T23:00:00Z"), in: berlin) == DayKey(year: 2026, month: 10, day: 27))
        let instant = date("2026-10-26T23:30:00Z")
        #expect(DayKey(instant, in: berlin) == DayKey(year: 2026, month: 10, day: 27))
        #expect(DayKey(instant, in: newYork) == DayKey(year: 2026, month: 10, day: 26))
        #expect(DayKey(instant, in: utc) == DayKey(year: 2026, month: 10, day: 26))
    }

    @Test func handlesTheNightTheClocksGoBack() {
        let night = DayKey(year: 2026, month: 10, day: 25)
        #expect(night.start(in: berlin) == date("2026-10-24T22:00:00Z"))
        #expect(night.adding(days: 1).start(in: berlin) == date("2026-10-25T23:00:00Z"))
        #expect(DayKey.night(endingAt: date("2026-10-25T06:30:00Z"), in: berlin) == night)
    }

    @Test func addsAndOrdersDaysAcrossMonthAndYearEnds() {
        #expect(DayKey(year: 2026, month: 12, day: 31).adding(days: 1) == DayKey(year: 2027, month: 1, day: 1))
        #expect(DayKey(year: 2026, month: 3, day: 1).adding(days: -1) == DayKey(year: 2026, month: 2, day: 28))
        #expect(DayKey(year: 2026, month: 9, day: 30) < DayKey(year: 2026, month: 10, day: 1))
    }

    @Test func todayComesFromTheInjectedClock() {
        let clock = FixedClock(now: date("2026-10-26T23:30:00Z"), timeZone: berlin)
        #expect(clock.today == DayKey(year: 2026, month: 10, day: 27))
    }
}
