import Foundation
import Testing
import VeselCore

struct FirstWeekTests {
    let today = day("2026-10-25")

    var status: RecoveryStatus {
        RecoveryStatus(NightlyRecharge(night: today, recoveryIndicator: 5, recoveryIndicatorSubLevel: 0))!
    }

    func lines(recovery: Int, sleep: Int, calmBaselineDays: Int = 0) -> DayLines {
        DayLines(
            recovery: InRange.recovery(status: status, earlierNights: recovery),
            sleep: LineVerdict(
                state: .learning(soFar: sleep, of: 7), explanation: Explanation(method: "", version: 0, inputs: [], text: ""), normal: .none, scale: nil),
            calm: InRange.calmBeforeBaseline(baselineDays: calmBaselineDays)
        )
    }

    func nights(_ days: [Int]) -> Set<DayKey> {
        Set(days.map { day("2026-10-\($0 < 10 ? "0" : "")\($0)") })
    }

    @Test func aMissedNightLeavesItsCheckEmptyAndTheRowOneLonger() throws {
        let came = nights([20, 21, 23, 24, 25])
        let week = try #require(
            FirstWeek.make(nights: came, sleepNights: came, readings: [:], shownNight: today, today: today, lines: lines(recovery: 4, sleep: 4)))
        let recovery = try #require(week.rows.first)
        #expect(recovery.line == .recovery)
        #expect(recovery.cells == [.checked, .checked, .missed, .checked, .checked, .checked, .ahead, .ahead])
        #expect(recovery.remaining == 2)
        #expect(recovery.normalFrom == day("2026-10-28"))
        #expect(recovery.text == "2 more nights · Wed")
        #expect(
            recovery.explanation.text
                == "Vesel needs 7 nights to learn your usual; 5 came in, 1 was missed. Your normal first shows on the morning after the 7th.")
        #expect(week.rows.map(\.line) == [.recovery, .sleep, .calm])
    }

    @Test func withSevenInTheNormalShowsTomorrow() throws {
        let came = nights([19, 20, 21, 22, 23, 24, 25])
        let week = try #require(
            FirstWeek.make(nights: came, sleepNights: came, readings: [:], shownNight: today, today: today, lines: lines(recovery: 6, sleep: 6)))
        #expect(week.rows.first?.text == "Your normal shows tomorrow")
        #expect(week.rows.first?.normalFrom == day("2026-10-26"))
    }

    @Test func calmCountsWellWornDaysUpToYesterday() throws {
        // Six days so far, the 22nd with too few readings; today's readings don't count yet.
        let readings: [DayKey: Int] = [
            day("2026-10-19"): 40, day("2026-10-20"): 35, day("2026-10-21"): 50, day("2026-10-22"): 4,
            day("2026-10-23"): 45, day("2026-10-24"): 38, today: 12,
        ]
        let all = nights(Array(1...25))
        let settled = DayLines(
            recovery: InRange.recovery(status: status, earlierNights: 20), sleep: InRange.sleep(nil),
            calm: InRange.calmBeforeBaseline(baselineDays: 5)
        )
        let week = try #require(FirstWeek.make(nights: all, sleepNights: all, readings: readings, shownNight: today, today: today, lines: settled))
        #expect(week.rows.map(\.line) == [.calm])
        let calm = try #require(week.rows.first)
        #expect(calm.cells.count == 15)
        #expect(calm.checked == 5)
        #expect(calm.missed == 1)
        #expect(calm.text == "about 9 more days")
        #expect(calm.normalFrom == nil)
    }

    @Test func calmShowsItsLongRowEvenWithNoDaysIn() throws {
        let came = nights([24, 25])
        let week = try #require(
            FirstWeek.make(nights: came, sleepNights: came, readings: [:], shownNight: today, today: today, lines: lines(recovery: 1, sleep: 1)))
        let calm = try #require(week.rows.first { $0.line == .calm })
        #expect(calm.cells == Array(repeating: .ahead, count: FirstWeek.calmDays))
        #expect(calm.text == "about \(FirstWeek.calmDays) more days")
    }

    @Test func goneOnceEveryLineHasItsNormal() {
        let all = nights(Array(1...25))
        let settled = DayLines(
            recovery: InRange.recovery(status: status, earlierNights: 20), sleep: InRange.sleep(nil),
            calm: InRange.calm(minutes: 10, previous: Array(repeating: 20, count: 10))
        )
        #expect(FirstWeek.make(nights: all, sleepNights: all, readings: [:], shownNight: today, today: today, lines: settled) == nil)
    }
}
