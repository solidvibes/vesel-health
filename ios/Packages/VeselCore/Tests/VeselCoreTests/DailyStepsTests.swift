import Foundation
import Testing
@testable import VeselCore

struct DailyStepsTests {
    let day = DayKey("2026-10-28")!

    func earlier(_ values: [Double]) -> [DayKey: Double] {
        Dictionary(uniqueKeysWithValues: values.enumerated().map { (day.adding(days: -($0.offset + 1)), $0.element) })
    }

    @Test func theNormalIsTheMeanPlusOrMinusOneSpreadOfThePreviousDays() {
        let steps = earlier([7000, 9000, 7000, 9000, 7000, 9000, 7000, 9000])
        #expect(DailySteps.normal(before: day, in: steps) == 7000...9000)
    }

    @Test func theDayItselfIsNotPartOfItsOwnNormal() {
        var steps = earlier([7000, 9000, 7000, 9000, 7000, 9000, 7000, 9000])
        steps[day] = 20_000
        #expect(DailySteps.normal(before: day, in: steps) == 7000...9000)
    }

    @Test func onlyThePreviousTwentyEightDaysCount() {
        var steps = earlier([7000, 9000, 7000, 9000, 7000, 9000, 7000, 9000])
        steps[day.adding(days: -29)] = 100_000
        #expect(DailySteps.normal(before: day, in: steps) == 7000...9000)
    }

    @Test func itNeedsSevenDays() {
        #expect(DailySteps.normal(before: day, in: earlier([8000, 9000, 7000, 8000, 9000, 7000])) == nil)
    }

    @Test func theNormalNeverGoesBelowZero() {
        let normal = DailySteps.normal(before: day, in: earlier([0, 0, 0, 0, 0, 0, 0, 7000]))
        #expect(normal?.lowerBound == 0)
    }

    @Test func theDayCarriesItsStepsAndWhenTheyWereRead() {
        let read = Date(timeIntervalSince1970: 1_780_000_000)
        let metric = DailySteps.metric(day: day, steps: 6240, readAt: read)
        #expect(metric.kind == MetricKind.steps)
        #expect(metric.value == 6240)
        #expect(metric.computedAt == read)
    }
}
