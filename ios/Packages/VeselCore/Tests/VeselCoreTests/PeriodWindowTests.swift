import Testing
import VeselCore

struct PeriodWindowTests {
    let today = day("2026-10-28")

    @Test func windowsEndOnTodayAndStepBackByTheirLength() {
        #expect(PeriodWindow.end(holding: today, period: .week, today: today) == today)
        #expect(PeriodWindow.end(holding: day("2026-10-22"), period: .week, today: today) == today)
        #expect(PeriodWindow.end(holding: day("2026-10-21"), period: .week, today: today) == day("2026-10-21"))
        #expect(PeriodWindow.end(holding: day("2026-10-20"), period: .week, today: today) == day("2026-10-21"))
        #expect(PeriodWindow.end(holding: day("2026-10-05"), period: .month, today: today) == today)
        #expect(PeriodWindow.end(holding: day("2026-09-30"), period: .month, today: today) == day("2026-09-30"))
        #expect(PeriodWindow.end(holding: day("2026-07-20"), period: .quarter, today: today) == day("2026-07-30"))
        #expect(PeriodWindow.end(holding: day("2026-10-10"), period: .day, today: today) == day("2026-10-10"))
        #expect(PeriodWindow.end(holding: day("2026-11-02"), period: .week, today: today) == today)
        #expect(PeriodWindow.first(endingOn: today, period: .month) == day("2026-10-01"))
    }

    @Test func pagesOnePeriodAndStopsAtToday() {
        let earlier = PeriodWindow.paged(end: today, by: -1, period: .week, today: today)
        #expect(earlier == day("2026-10-21"))
        #expect(PeriodWindow.paged(end: earlier, by: 1, period: .week, today: today) == today)
        #expect(PeriodWindow.paged(end: today, by: 1, period: .week, today: today) == today)
        #expect(PeriodWindow.canPageLater(end: earlier, today: today))
        #expect(!PeriodWindow.canPageLater(end: today, today: today))
    }

    @Test func pagesRunFromTheWindowHoldingTheFirstDayToToday() {
        #expect(
            PeriodWindow.pages(period: .day, holding: today, firstDay: day("2026-10-25"), today: today)
                == ["2026-10-25", "2026-10-26", "2026-10-27", "2026-10-28"].map(day))
        #expect(
            PeriodWindow.pages(period: .week, holding: today, firstDay: day("2026-10-10"), today: today)
                == ["2026-10-14", "2026-10-21", "2026-10-28"].map(day))
        #expect(
            PeriodWindow.pages(period: .quarter, holding: today, firstDay: day("2026-06-01"), today: today)
                == ["2026-07-30", "2026-10-28"].map(day))
    }

    @Test func pagesWithoutAFirstDayAreTheOpenedWindowOnly() {
        #expect(PeriodWindow.pages(period: .week, holding: day("2026-10-20"), firstDay: nil, today: today) == [day("2026-10-21")])
    }

    @Test func pagesReachADayOpenedBeforeTheFirstDayWithData() {
        #expect(
            PeriodWindow.pages(period: .day, holding: day("2026-10-24"), firstDay: day("2026-10-26"), today: today)
                == ["2026-10-24", "2026-10-25", "2026-10-26", "2026-10-27", "2026-10-28"].map(day))
    }

    @Test func weeksAcrossTheClockChangesStillHaveSevenDays() {
        let europe = PeriodWindow.days(endingOn: day("2026-10-28"), period: .week)
        #expect(europe.first == day("2026-10-22"))
        #expect(europe.contains(day("2026-10-25")))
        #expect(europe.count == 7)
        let us = PeriodWindow.days(endingOn: day("2026-11-03"), period: .week)
        #expect(us.first == day("2026-10-28"))
        #expect(us.contains(day("2026-11-01")))
        #expect(us.count == 7)
        #expect(PeriodWindow.end(holding: day("2026-10-25"), period: .week, today: day("2026-11-01")) == day("2026-10-25"))
        #expect(PeriodWindow.days(endingOn: today, period: .quarter).count == 90)
    }

    @Test func theMostFrequentWordWinsAndATieGoesToTheNewerNight() {
        let nights: [(day: DayKey, value: String)] = [
            (day("2026-10-24"), "OK"), (day("2026-10-25"), "good"), (day("2026-10-26"), "OK"), (day("2026-10-27"), "good"), (day("2026-10-28"), "poor"),
        ]
        #expect(PeriodWindow.mostFrequent(nights) == "good")
        #expect(PeriodWindow.mostFrequent(Array(nights.dropLast())) == "good")
        #expect(PeriodWindow.mostFrequent(Array(nights.prefix(3))) == "OK")
        #expect(PeriodWindow.mostFrequent([(day: today, value: "OK")]) == "OK")
        #expect(PeriodWindow.mostFrequent([(day: DayKey, value: String)]()) == nil)
    }

    @Test func averagesOnlyTheValuesThereAre() {
        #expect(PeriodWindow.average([6, 7.5, 9]) == 7.5)
        #expect(PeriodWindow.average([]) == nil)
    }
}
