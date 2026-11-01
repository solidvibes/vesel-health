import Foundation
import Testing
@testable import VeselCore

struct DailyHeartRateTests {
    private func period(_ iso: String, _ mean: Double) -> FiveMinuteMean {
        FiveMinuteMean(period: Int64(at(iso).timeIntervalSince1970) / FiveMinuteMean.seconds, mean: mean)
    }

    @Test func eachDayKeepsItsAverageLowestAndHighestWithTheirTimes() throws {
        // Berlin is UTC+1 on 2026-10-26: 08:00Z is 09:00.
        let metrics = DailyHeartRate.days(
            periods: [
                period("2026-10-26T08:05:00Z", 70), period("2026-10-26T08:00:00Z", 60), period("2026-10-26T09:00:00Z", 110),
                period("2026-10-27T08:00:00Z", 80),
            ],
            zone: berlin, computedAt: at("2026-10-27T12:00:00Z")
        )
        #expect(metrics.map(\.day) == [day("2026-10-26"), day("2026-10-27")])
        #expect(metrics.map(\.value) == [80, 80])
        let first = metrics[0]
        #expect(first.kind == "hr.dayMean")
        #expect(first.explanation.method == "hr.dayRange")
        #expect(first.explanation.version == 1)
        #expect(
            first.explanation.inputs == [
                .init(name: "lowest", value: 60, unit: "bpm"),
                .init(name: "lowestAt", value: at("2026-10-26T08:00:00Z").timeIntervalSince1970, unit: "s"),
                .init(name: "highest", value: 110, unit: "bpm"),
                .init(name: "highestAt", value: at("2026-10-26T09:00:00Z").timeIntervalSince1970, unit: "s"),
                .init(name: "periods", value: 3, unit: "periods"),
            ])
        #expect(
            first.explanation.text
                == "On this day the Loop's 5-minute averages ran from 60 bpm at 09:00 to 110 bpm at 10:00. Their average was 80 bpm, from 3 five-minute periods."
        )
        let range = try #require(DailyHeartRate.Range(first))
        #expect(range.lowest == 60)
        #expect(range.lowestAt == at("2026-10-26T08:00:00Z"))
        #expect(range.highest == 110)
        #expect(range.highestAt == at("2026-10-26T09:00:00Z"))
        #expect(range.periods == 3)
    }

    @Test func aTieGoesToTheEarlierPeriod() throws {
        let metrics = DailyHeartRate.days(
            periods: [
                period("2026-10-26T09:00:00Z", 50), period("2026-10-26T08:00:00Z", 50), period("2026-10-26T10:00:00Z", 90), period("2026-10-26T07:00:00Z", 90),
            ],
            zone: berlin, computedAt: at("2026-10-27T12:00:00Z")
        )
        let range = try #require(DailyHeartRate.Range(metrics[0]))
        #expect(range.lowestAt == at("2026-10-26T08:00:00Z"))
        #expect(range.highestAt == at("2026-10-26T07:00:00Z"))
    }

    @Test func aLonePeriodIsItsOwnLowestHighestAndAverage() throws {
        let metrics = DailyHeartRate.days(periods: [period("2026-10-26T08:00:00Z", 62)], zone: berlin, computedAt: at("2026-10-27T12:00:00Z"))
        let range = try #require(DailyHeartRate.Range(metrics[0]))
        #expect(metrics[0].value == 62)
        #expect(range.lowest == 62 && range.highest == 62 && range.periods == 1)
        #expect(metrics[0].explanation.text == "On this day the Loop's only 5-minute average was 62 bpm at 09:00.")
    }

    @Test func rangeIsNilForAnotherMethod() {
        let other = ComputedMetric(
            kind: MetricKind.heartRateDayMean, day: day("2026-10-26"), hour: nil, value: 70, unit: "bpm",
            explanation: Explanation(method: "hr.dayMean", version: 1, inputs: [.init(name: "periods", value: 2, unit: "periods")], text: ""),
            computedAt: at("2026-10-27T12:00:00Z")
        )
        #expect(DailyHeartRate.Range(other) == nil)
    }

    @Test func periodsGroupAcrossTheZonesMidnight() {
        // Berlin is UTC+1 on 2026-10-26: 22:55Z is 23:55 that day, 23:00Z is 00:00 the next.
        let metrics = DailyHeartRate.days(
            periods: [period("2026-10-26T22:55:00Z", 50), period("2026-10-26T23:00:00Z", 90)],
            zone: berlin, computedAt: at("2026-10-27T12:00:00Z")
        )
        #expect(metrics.map(\.day) == [day("2026-10-26"), day("2026-10-27")])
        #expect(metrics.map(\.value) == [50, 90])
    }

    @Test func theDayClocksGoBackHasTwentyFiveHours() {
        // Berlin leaves summer time on 2026-10-25: the day runs from 22:00Z on the 24th to 23:00Z on the 25th.
        let metrics = DailyHeartRate.days(
            periods: [
                period("2026-10-24T21:55:00Z", 40),
                period("2026-10-24T22:00:00Z", 60),
                period("2026-10-25T22:55:00Z", 80),
                period("2026-10-25T23:00:00Z", 100),
            ],
            zone: berlin, computedAt: at("2026-10-26T12:00:00Z")
        )
        #expect(metrics.map(\.day) == [day("2026-10-24"), day("2026-10-25"), day("2026-10-26")])
        #expect(metrics.map(\.value) == [40, 70, 100])
        let range = DailyHeartRate.Range(metrics[1])
        #expect(range?.lowest == 60 && range?.highest == 80)
        #expect(range?.highestAt == at("2026-10-25T22:55:00Z"))
    }

    @Test func noPeriodsGiveNoDays() {
        #expect(DailyHeartRate.days(periods: [], zone: berlin, computedAt: at("2026-10-27T12:00:00Z")).isEmpty)
    }
}
