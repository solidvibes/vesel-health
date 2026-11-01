import Foundation
import Testing
@testable import VeselCore

struct StressBaselineTests {
    let today = day("2026-10-26")

    /// Ten readings a day, ln RMSSD 2.0, 2.1 … 2.9.
    let tenReadings = (0..<10).map { 2.0 + 0.1 * Double($0) }

    func days(_ offsets: [Int], readings: [Double]? = nil) -> [DayKey: [Double]] {
        Dictionary(uniqueKeysWithValues: offsets.map { (today.adding(days: -$0), readings ?? tenReadings) })
    }

    @Test func sevenDaysOfTenReadingsMakeTheBaseline() throws {
        // 70 values, each of the ten repeated seven times, sorted. The 80th percentile sits at position 0.8 × 69 = 55.2:
        // index 55 is 2.7 and index 56 is 2.8, so 2.7 + 0.2 × 0.1 = 2.72. The 5th is at 3.45, between two 2.0s: 2.0.
        guard case .ready(let baseline) = StressBaseline.make(before: today, valuesByDay: days(Array(1...7))) else {
            Issue.record("expected a baseline")
            return
        }
        #expect(abs(baseline.baseline - 2.72) < 1e-9)
        #expect(baseline.floor == 2.0)
        #expect(baseline.days == 7)
        #expect(baseline.windows == 70)
    }

    @Test func sixDaysAreStillLearningAndSevenAreEnough() {
        #expect(StressBaseline.make(before: today, valuesByDay: days(Array(1...6))) == .learning(days: 6))
        if case .learning = StressBaseline.make(before: today, valuesByDay: days(Array(1...7))) {
            Issue.record("seven days should be enough")
        }
        #expect(StressBaseline.make(before: today, valuesByDay: [:]) == .learning(days: 0))
    }

    @Test func aDayWithFewerThanTenReadingsDoesNotCount() {
        var values = days(Array(1...6))
        values[today.adding(days: -7)] = Array(tenReadings.dropFirst())
        #expect(StressBaseline.make(before: today, valuesByDay: values) == .learning(days: 6))
    }

    @Test func onlyTheFourteenDaysBeforeCountAndNeverTheDayItself() {
        var values = days([0, 15, 16, 17, 18, 19, 20])
        #expect(StressBaseline.make(before: today, valuesByDay: values) == .learning(days: 0))
        values = days([1, 2, 3, 4, 5, 6, 14])
        if case .learning = StressBaseline.make(before: today, valuesByDay: values) {
            Issue.record("day 14 is still inside the window")
        }
    }

    @Test func qualifyingDaysCountsTheSameWay() {
        let counts = [today.adding(days: -1): 10, today.adding(days: -2): 9, today.adding(days: -3): 25, today: 99, today.adding(days: -15): 50]
        #expect(StressBaseline.qualifyingDays(before: today, counts: counts) == 2)
    }

    @Test func levelsAreWrittenOut() {
        let baseline = StressBaseline(baseline: 2.72, floor: 2.0, days: 7, windows: 70)
        #expect(abs(baseline.level(of: 2.36) - 50) < 1e-9)
        #expect(baseline.level(of: 2.72) == 0)
        #expect(baseline.level(of: 3.5) == 0)
        #expect(baseline.level(of: 2.0) == 100)
        #expect(baseline.level(of: 1.0) == 100)
        #expect(abs(baseline.level(of: 2.5) - 0.22 / 0.72 * 100) < 1e-9)
    }

    @Test func aFlatBaselineJudgesAnythingBelowItAsHigh() {
        let flat = StressBaseline(baseline: 3, floor: 3, days: 7, windows: 70)
        #expect(flat.level(of: 2.9) == 100)
        #expect(flat.level(of: 3) == 0)
    }

    @Test func theBandsSplitAt34And67() {
        #expect(StressLevel(level: 0) == .calm)
        #expect(StressLevel(level: 33.49) == .calm)
        #expect(StressLevel(level: 33.5) == .moderate)
        #expect(StressLevel(level: 34) == .moderate)
        #expect(StressLevel(level: 66.49) == .moderate)
        #expect(StressLevel(level: 66.5) == .high)
        #expect(StressLevel(level: 67) == .high)
        #expect(StressLevel(level: 100) == .high)
    }

    @Test func percentilesInterpolateBetweenTheTwoNearestValues() {
        let values = (1...11).map(Double.init)
        #expect(StressBaseline.percentile(values, 0.8) == 9)
        #expect(StressBaseline.percentile(values, 0.05) == 1.5)
        #expect(StressBaseline.percentile([4], 0.8) == 4)
    }
}
