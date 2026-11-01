import Foundation
import Testing
@testable import VeselCore

struct DayBucketsTests {
    private func group(_ times: [String], minutes: Int?) -> [DayBucket<Date>] {
        DayBuckets.group(times.map(at), time: { $0 }, minutes: minutes, zone: berlin)
    }

    @Test func bucketsStartAtTheZonesMidnightNotUTCs() {
        // Berlin is UTC+1 on 2026-10-26: 22:55Z is 23:55, in the 22:00 to 24:00 bucket; 23:00Z is 00:00 the next day.
        let buckets = group(["2026-10-26T22:55:00Z", "2026-10-26T23:00:00Z", "2026-10-26T20:59:00Z"], minutes: 120)
        #expect(buckets.map(\.start) == [at("2026-10-26T19:00:00Z"), at("2026-10-26T21:00:00Z"), at("2026-10-26T23:00:00Z")])
        #expect(buckets.map(\.end) == [at("2026-10-26T21:00:00Z"), at("2026-10-26T23:00:00Z"), at("2026-10-27T01:00:00Z")])
        #expect(buckets.map(\.items.count) == [1, 1, 1])
    }

    @Test func emptyBucketsAreAbsentAndItemsShareABucket() {
        let buckets = group(["2026-10-26T13:00:00Z", "2026-10-26T13:25:00Z", "2026-10-26T14:30:00Z"], minutes: 30)
        #expect(buckets.map(\.start) == [at("2026-10-26T13:00:00Z"), at("2026-10-26T14:30:00Z")])
        #expect(buckets.map(\.items.count) == [2, 1])
    }

    @Test func nilMinutesGivesWholeCalendarDays() {
        let buckets = group(["2026-10-26T22:55:00Z", "2026-10-26T23:00:00Z", "2026-10-27T08:00:00Z"], minutes: nil)
        #expect(buckets.map(\.day) == [day("2026-10-26"), day("2026-10-27")])
        #expect(buckets.map(\.start) == [at("2026-10-25T23:00:00Z"), at("2026-10-26T23:00:00Z")])
        #expect(buckets.map(\.end) == [at("2026-10-26T23:00:00Z"), at("2026-10-27T23:00:00Z")])
        #expect(buckets.map(\.items.count) == [1, 2])
    }

    @Test func theTwentyFiveHourDayHasTwentyFiveHourBucketsAndAShortLastFourHourOne() {
        // Berlin leaves summer time on 2026-10-25: the day runs from 22:00Z on the 24th to 23:00Z on the 25th.
        let hourly = group(["2026-10-24T22:00:00Z", "2026-10-25T22:00:00Z", "2026-10-25T22:59:00Z"], minutes: 60)
        #expect(hourly.map(\.start) == [at("2026-10-24T22:00:00Z"), at("2026-10-25T22:00:00Z")])
        #expect(hourly.map(\.items.count) == [1, 2])
        let fourHourly = group(["2026-10-25T18:00:00Z", "2026-10-25T22:00:00Z", "2026-10-25T23:00:00Z"], minutes: 240)
        #expect(fourHourly.map(\.start) == [at("2026-10-25T18:00:00Z"), at("2026-10-25T22:00:00Z"), at("2026-10-25T23:00:00Z")])
        #expect(fourHourly.map(\.end) == [at("2026-10-25T22:00:00Z"), at("2026-10-25T23:00:00Z"), at("2026-10-26T03:00:00Z")])
    }

    @Test func theTwentyThreeHourDayHasAShortLastBucket() {
        // Berlin springs forward on 2026-03-29: the day runs from 23:00Z on the 28th to 22:00Z on the 29th.
        let buckets = group(["2026-03-29T21:30:00Z"], minutes: 120)
        #expect(buckets.map(\.start) == [at("2026-03-29T21:00:00Z")])
        #expect(buckets.map(\.end) == [at("2026-03-29T22:00:00Z")])
        #expect(DayBuckets.clock(at("2026-03-29T21:30:00Z"), zone: berlin) == "23:30")
    }

    @Test func noItemsGiveNoBuckets() {
        #expect(group([], minutes: 60).isEmpty)
    }
}
