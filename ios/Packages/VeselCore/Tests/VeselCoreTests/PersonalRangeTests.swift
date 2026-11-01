import Foundation
import Testing
import VeselCore

struct PersonalRangeTests {
    /// Seven nights: mean 46, deviations −6 −4 −2 0 2 4 6, squares add to 112, 112 ÷ 7 = 16, so the SD is exactly 4.
    let seven: [Double] = [40, 42, 44, 46, 48, 50, 52]

    @Test func usualIsTheMeanPlusOrMinusOneSD() throws {
        let range = try #require(PersonalRange(previous: seven))
        #expect(range.mean == 46)
        #expect(range.sd == 4)
        #expect(range.low == 42)
        #expect(range.high == 50)
        #expect(range.nights == 7)
    }

    @Test func sixNightsAreStillLearningAndSevenAreEnough() {
        #expect(PersonalRange(previous: Array(seven.dropFirst())) == nil)
        #expect(PersonalRange(previous: seven) != nil)
        #expect(PersonalRange(previous: []) == nil)
    }

    @Test func verdictsSplitAtOneAndTwoSDs() throws {
        let range = try #require(PersonalRange(previous: seven))
        #expect(range.verdict(of: 46) == .usual)
        #expect(range.verdict(of: 50) == .usual)
        #expect(range.verdict(of: 42) == .usual)
        #expect(range.verdict(of: 50.1) == .higher)
        #expect(range.verdict(of: 54) == .higher)
        #expect(range.verdict(of: 54.5) == .wellAbove)
        #expect(range.verdict(of: 41.9) == .lower)
        #expect(range.verdict(of: 38) == .lower)
        #expect(range.verdict(of: 37.9) == .wellBelow)
    }

    @Test func aFlatHistoryJudgesAnyChange() throws {
        let range = try #require(PersonalRange(previous: Array(repeating: 50, count: 7)))
        #expect(range.sd == 0)
        #expect(range.verdict(of: 50) == .usual)
        #expect(range.verdict(of: 51) == .higher)
        #expect(range.verdict(of: 49) == .lower)
    }

    @Test func theRangeIsThe28NightsBeforeAndNeverTheNightItself() {
        let night = day("2026-10-26")
        var values: [DayKey: Double] = [night: 999]
        for offset in 1...30 { values[night.adding(days: -offset)] = Double(offset) }
        let previous = PersonalRange.previousValues(before: night, in: values)
        #expect(previous.count == 28)
        #expect(previous.sorted() == (1...28).map(Double.init))
    }

    @Test func missingNightsAreSkippedNotCounted() {
        let night = day("2026-10-26")
        let values: [DayKey: Double] = [night.adding(days: -1): 40, night.adding(days: -3): 44, night.adding(days: -40): 1]
        #expect(PersonalRange.previousValues(before: night, in: values).sorted() == [40, 44])
    }

    @Test func theWordsMatchTheVerdicts() {
        #expect(RangeVerdict.wellBelow.word == "much lower than usual")
        #expect(RangeVerdict.lower.word == "lower than usual")
        #expect(RangeVerdict.usual.word == "usual")
        #expect(RangeVerdict.higher.word == "higher than usual")
        #expect(RangeVerdict.wellAbove.word == "much higher than usual")
        #expect(RangeVerdict.learning(nights: 3).word == nil)
    }

    private func metric(_ night: String, _ value: Double) -> ComputedMetric {
        ComputedMetric(
            kind: "k", day: DayKey(night)!, hour: nil, value: value, unit: "u",
            explanation: Explanation(method: "m", version: 1, inputs: [], text: ""), computedAt: Date(timeIntervalSince1970: 0)
        )
    }

    /// Nights 2026-10-01 … 2026-10-07 hold `seven`; the night judged is 2026-10-08.
    private var sevenEarlier: [ComputedMetric] {
        seven.enumerated().map { metric("2026-10-0\($0.offset + 1)", $0.element) }
    }

    @Test func latestUsesTheNewestNightAgainstTheSevenBeforeIt() throws {
        let range = try #require(PersonalRange.latest(of: sevenEarlier + [metric("2026-10-08", 99)]))
        #expect(range.mean == 46)
        #expect(range.sd == 4)
        #expect(range.nights == 7)
    }

    @Test func latestNeedsSevenEarlierNights() {
        #expect(PersonalRange.latest(of: Array(sevenEarlier.dropFirst()) + [metric("2026-10-08", 99)]) == nil)
        #expect(PersonalRange.latest(of: []) == nil)
    }

    @Test func latestSkipsGapsAndIgnoresNightsOlderThan28() throws {
        let gappy = sevenEarlier.filter { $0.day != DayKey("2026-10-04")! } + [metric("2026-10-08", 99)]
        #expect(PersonalRange.latest(of: gappy) == nil)
        let old = metric("2026-09-09", 1000)
        let range = try #require(PersonalRange.latest(of: [old] + sevenEarlier + [metric("2026-10-08", 99)]))
        #expect(range.mean == 46)
        #expect(range.nights == 7)
        let edge = metric("2026-09-10", 1000)
        #expect(PersonalRange.latest(of: [edge] + sevenEarlier + [metric("2026-10-08", 99)])?.nights == 8)
    }

    @Test func settlingNeedsTwoValues() {
        #expect(PersonalRange.settling(of: []) == nil)
        #expect(PersonalRange.settling(of: [metric("2026-10-01", 50)]) == nil)
    }

    @Test func settlingOfTwoIsTheirMean() throws {
        let found = try #require(PersonalRange.settling(of: [metric("2026-10-01", 40), metric("2026-10-02", 50)]))
        #expect(found.median == 45)
        #expect(found.earlierNights == 1)
    }

    @Test func settlingMedianOfOddAndEvenCounts() throws {
        let odd = try #require(PersonalRange.settling(of: [metric("2026-10-01", 60), metric("2026-10-02", 40), metric("2026-10-03", 50)]))
        #expect(odd.median == 50)
        #expect(odd.earlierNights == 2)
        let even = try #require(
            PersonalRange.settling(of: [
                metric("2026-10-01", 60), metric("2026-10-02", 40), metric("2026-10-03", 50), metric("2026-10-04", 52),
            ]))
        #expect(even.median == 51)
        #expect(even.earlierNights == 3)
    }

    @Test func settlingCountsOnlyNightsWithAValueAndIgnoresOlderThan28() throws {
        let found = try #require(
            PersonalRange.settling(of: [metric("2026-09-01", 1000), metric("2026-10-01", 40), metric("2026-10-05", 44), metric("2026-10-06", 48)]))
        #expect(found.earlierNights == 2)
        #expect(found.median == 44)
    }
}
