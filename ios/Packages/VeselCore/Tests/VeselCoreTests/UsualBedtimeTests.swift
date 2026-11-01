import Foundation
import Testing
import VeselCore

struct UsualBedtimeTests {
    /// Berlin is UTC+1 on 2026-10-26.
    func starts(_ times: [String]) -> [Date] {
        times.map { at("2026-10-26T\($0):00+01:00") }
    }

    @Test func theMiddleStartCountedFromSixInTheEvening() throws {
        let bedtime = try #require(UsualBedtime.make(starts: starts(["23:05", "23:20", "22:50", "00:10", "23:15", "23:00", "23:30"]), zone: berlin))
        #expect(bedtime.text == "23:15")
        #expect(bedtime.explanation.method == "usualBedtime")
        #expect(bedtime.explanation.version == 1)
    }

    @Test func anEvenCountAveragesTheMiddleTwoAndRoundsToFiveMinutes() throws {
        // Middle two: 23:50 and 00:04, so 23:57, rounded to 23:55.
        let bedtime = try #require(UsualBedtime.make(starts: starts(["23:00", "23:10", "23:50", "00:04", "00:20", "00:30", "23:40", "00:15"]), zone: berlin))
        #expect(bedtime.text == "23:55")
    }

    @Test func sixNightsAreTooFew() {
        #expect(UsualBedtime.make(starts: starts(["23:05", "23:20", "22:50", "00:10", "23:15", "23:00"]), zone: berlin) == nil)
    }
}
