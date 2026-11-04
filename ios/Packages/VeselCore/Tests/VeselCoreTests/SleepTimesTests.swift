import Foundation
import Testing
import VeselCore

struct SleepTimesTests {
    /// Berlin is UTC+1 on 2026-10-26.
    func night(_ start: String, _ end: String, _ day: Int = 26) -> SleepNightTimes {
        SleepNightTimes(night: DayKey(year: 2026, month: 10, day: day), start: at("2026-10-26T\(start):00+01:00"), end: at("2026-10-27T\(end):00+01:00"))
    }

    @Test func theMiddleBedtimeAndWakeAcrossMidnight() throws {
        let times = try #require(
            SleepTimes.make(nights: [night("23:05", "07:00"), night("23:20", "07:10"), night("00:10", "07:30")], zone: berlin))
        #expect(times.bedtime == "23:20")
        #expect(times.wake == "07:10")
        #expect(times.text == "23:20 to 07:10")
        #expect(times.explanation.method == "sleepTimes")
        #expect(times.explanation.version == 1)
    }

    @Test func anEvenCountAveragesTheMiddleTwoAndRoundsToFiveMinutes() throws {
        // Starts: middle two 23:50 and 00:04, so 23:57 rounds to 23:55. Wakes: 07:00 and 07:09 make 07:04.5, so 07:05.
        let times = try #require(
            SleepTimes.make(nights: [night("23:00", "06:00"), night("23:50", "07:00"), night("00:04", "07:09"), night("00:30", "08:00")], zone: berlin))
        #expect(times.bedtime == "23:55")
        #expect(times.wake == "07:05")
    }

    @Test func aWakeAfterNoonIsStillCountedFromSixInTheEvening() throws {
        let times = try #require(SleepTimes.make(nights: [night("23:00", "13:30")], zone: berlin))
        #expect(times.wake == "13:30")
    }

    @Test func aBedtimeBeforeSixInTheEveningSortsAfterEveryLateOne() throws {
        let times = try #require(SleepTimes.make(nights: [night("17:30", "06:00"), night("23:00", "06:00"), night("23:30", "06:00")], zone: berlin))
        #expect(times.bedtime == "23:30")
    }

    @Test func noNightsHaveNoTimes() {
        #expect(SleepTimes.make(nights: [], zone: berlin) == nil)
    }
}
