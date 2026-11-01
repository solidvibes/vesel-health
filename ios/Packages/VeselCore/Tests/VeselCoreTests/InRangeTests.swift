import Foundation
import Testing
@testable import VeselCore

struct InRangeTests {
    private func status(_ indicator: Int, _ sub: Int) -> RecoveryStatus {
        RecoveryStatus(NightlyRecharge(night: day("2026-10-26"), recoveryIndicator: indicator, recoveryIndicatorSubLevel: sub))!
    }

    private func sleep(_ asleep: Double, mean: Double? = nil, sd: Double? = nil, nights: Int) -> ContributorReading {
        var inputs: [Explanation.Input] = [.init(name: "value", value: asleep, unit: "min"), .init(name: "nights", value: Double(nights), unit: "nights")]
        if let mean, let sd {
            inputs += [.init(name: "usualMean", value: mean, unit: "min"), .init(name: "usualSD", value: sd, unit: "min")]
        }
        return ContributorReading(
            ComputedMetric(
                kind: Contributor.sleep.kind, day: day("2026-10-26"), hour: nil, value: asleep, unit: "min",
                explanation: Explanation(method: RecoveryContributors.method, version: 1, inputs: inputs, text: ""),
                computedAt: at("2026-10-26T06:00:00Z")
            ))!
    }

    private func near(_ actual: Double?, _ expected: Double) -> Bool {
        guard let actual else { return false }
        return abs(actual - expected) < 0.001
    }

    @Test func recoveryIsInsideFromPolarsOK() {
        let verdict = InRange.recovery(status: status(4, 0), earlierNights: 7)
        #expect(verdict.state == .inside)
        #expect(!verdict.state.isOutside)
        #expect(verdict.normal == LineNormal(low: 4))
        #expect(verdict.explanation.method == "inRange")
        #expect(verdict.explanation.version == 2)
        #expect(InRange.version == 2)
        #expect(verdict.explanation.text == "Polar's Nightly Recharge is OK (4 of 6): OK or better is inside your normal.")
    }

    @Test func recoveryPutsTheDotOnA1To6Track() {
        // 5 + 0.40 = 5.4: (5.4 − 1) ÷ 5 = 0.88; the normal runs 4 to 6: 0.6 to 1.
        let inside = InRange.recovery(status: status(5, 40), earlierNights: 20)
        #expect(inside.state == .inside)
        #expect(near(inside.scale?.dot, 0.88))
        #expect(near(inside.scale?.normalFrom, 0.6))
        #expect(near(inside.scale?.normalTo, 1))
        #expect(inside.explanation.text == "Polar's Nightly Recharge is good (5 of 6): OK or better is inside your normal.")
        // 3 + 0.99 = 3.99: (3.99 − 1) ÷ 5 = 0.598.
        let below = InRange.recovery(status: status(3, 99), earlierNights: 20)
        #expect(below.state == .below)
        #expect(below.state.isOutside)
        #expect(near(below.scale?.dot, 0.598))
        #expect(below.explanation.text == "Polar's Nightly Recharge is compromised (3 of 6), below your normal, which starts at OK.")
        // 6 + 1.00 = 7, held at the end of the track.
        #expect(near(InRange.recovery(status: status(6, 100), earlierNights: 20).scale?.dot, 1))
        #expect(near(InRange.recovery(status: status(1, 0), earlierNights: 20).scale?.dot, 0))
    }

    @Test func recoveryLearnsForSevenNightsAndIsEmptyWithoutAStatus() {
        let learning = InRange.recovery(status: status(5, 0), earlierNights: 6)
        #expect(learning.state == .learning(soFar: 6, of: 7))
        #expect(learning.scale == nil)
        #expect(learning.normal == .none)
        #expect(learning.explanation.text == "Learning your normal: 6 of 7 earlier nights so far.")
        let none = InRange.recovery(status: nil, earlierNights: 20)
        #expect(none.state == .none)
        #expect(none.scale == nil)
        #expect(none.explanation.text == "Polar hasn't scored this night.")
    }

    @Test func sleepIsInsideFromOneSDUnderToTwoSDOver() {
        // Mean 440, SD 35: normal 405 to 510. Spread 105, so the track runs 300 to 615 (315 wide).
        let verdict = InRange.sleep(sleep(430, mean: 440, sd: 35, nights: 26))
        #expect(verdict.state == .inside)
        #expect(verdict.normal == LineNormal(low: 405, high: 510))
        #expect(near(verdict.scale?.normalFrom, 105.0 / 315))
        #expect(near(verdict.scale?.normalTo, 210.0 / 315))
        #expect(near(verdict.scale?.dot, 130.0 / 315))
        #expect(verdict.scale?.value == 430)
        #expect(
            verdict.explanation.text
                == "7 h 10 m asleep; your normal is 6 h 45 m to 8 h 30 m (from 1 SD under to 2 SD over the mean of your previous 26 nights), so this night is inside it."
        )
        #expect(InRange.sleep(sleep(510, mean: 440, sd: 35, nights: 26)).state == .inside)
        #expect(InRange.sleep(sleep(405, mean: 440, sd: 35, nights: 26)).state == .inside)
    }

    @Test func sleepBelowTheBottomIsOutside() {
        let verdict = InRange.sleep(sleep(380, mean: 440, sd: 35, nights: 26))
        #expect(verdict.state == .below)
        #expect(verdict.state.isOutside)
        #expect(near(verdict.scale?.dot, 80.0 / 315))
        #expect(
            verdict.explanation.text
                == "6 h 20 m asleep; your normal is 6 h 45 m to 8 h 30 m (from 1 SD under to 2 SD over the mean of your previous 26 nights), so this night is below it."
        )
    }

    @Test func sleepBeyondTwoSDOverIsAboveAndHeldAtTheEndOfTheTrack() {
        // 1 SD over is still inside (the bottom stays at 1 SD under); only beyond 2 SD is above.
        #expect(InRange.sleep(sleep(475, mean: 440, sd: 35, nights: 26)).state == .inside)
        let above = InRange.sleep(sleep(560, mean: 440, sd: 35, nights: 26))
        #expect(above.state == .above)
        #expect(above.state.isOutside)
        #expect(near(above.scale?.dot, 260.0 / 315))
        #expect(
            above.explanation.text
                == "9 h 20 m asleep; your normal is 6 h 45 m to 8 h 30 m (from 1 SD under to 2 SD over the mean of your previous 26 nights), so this night is above it."
        )
        #expect(near(InRange.sleep(sleep(700, mean: 440, sd: 35, nights: 26)).scale?.dot, 1))
    }

    @Test func sleepTrackSpreadHasAOneHourFloor() {
        // SD 10: normal 430 to 460 (30 wide), so the spread is 60 and the track runs 370 to 520.
        let verdict = InRange.sleep(sleep(445, mean: 440, sd: 10, nights: 26))
        #expect(near(verdict.scale?.normalFrom, 60.0 / 150))
        #expect(near(verdict.scale?.normalTo, 90.0 / 150))
        #expect(near(verdict.scale?.dot, 75.0 / 150))
    }

    @Test func sleepLearnsWithoutARangeAndIsEmptyWithoutAReading() {
        let verdict = InRange.sleep(sleep(400, nights: 3))
        #expect(verdict.state == .learning(soFar: 3, of: 7))
        #expect(verdict.normal == .none)
        #expect(verdict.scale == nil)
        #expect(InRange.sleep(nil).state == .none)
        #expect(InRange.sleep(nil).scale == nil)
        #expect(InRange.sleep(nil).explanation.text == "No sleep recorded this night.")
    }

    @Test func calmIsInsideUpToTheAllowance() {
        // Mean 5, SD 3: mean + SD is 8, so the 15-minute floor is the allowance; the track runs 0 to 30.
        let verdict = InRange.calm(minutes: 10, previous: [2, 8, 2, 8, 2, 8, 2, 8])
        #expect(verdict.state == .inside)
        #expect(verdict.normal == LineNormal(high: 15))
        #expect(near(verdict.scale?.dot, 10.0 / 30))
        #expect(
            verdict.explanation.text
                == "10 m of high stress; your usual is up to 15 m (mean + 1 SD of your previous 8 days, at least 15 m), so this day is inside it.")
    }

    @Test func calmAboveTheAllowanceIsOutside() {
        // Mean 20, SD 10: allowance 30; the track runs 0 to 60.
        let previous: [Double] = [10, 30, 10, 30, 10, 30, 10, 30]
        let inside = InRange.calm(minutes: 12, previous: previous)
        #expect(inside.state == .inside)
        #expect(near(inside.scale?.dot, 0.2))
        #expect(near(inside.scale?.normalFrom, 0))
        #expect(near(inside.scale?.normalTo, 0.5))
        let above = InRange.calm(minutes: 45, previous: previous)
        #expect(above.state == .above)
        #expect(above.state.isOutside)
        #expect(above.normal == LineNormal(high: 30))
        #expect(near(above.scale?.dot, 0.75))
        #expect(
            above.explanation.text
                == "45 m of high stress; your usual is up to 30 m (mean + 1 SD of your previous 8 days, at least 15 m), so this day is above it.")
        #expect(near(InRange.calm(minutes: 90, previous: previous).scale?.dot, 1))
    }

    @Test func calmWithAnAllZeroHistoryAllowsFifteenMinutes() {
        let verdict = InRange.calm(minutes: 20, previous: Array(repeating: 0, count: 7))
        #expect(verdict.normal == LineNormal(high: 15))
        #expect(verdict.state == .above)
    }

    @Test func calmLearnsForSevenDaysAndIsEmptyForADayThatDoesNotCount() {
        let learning = InRange.calm(minutes: 30, previous: [5, 5, 5, 5, 5, 5])
        #expect(learning.state == .learning(soFar: 6, of: 7))
        #expect(learning.scale == nil)
        #expect(learning.explanation.text == "Learning your normal: 6 of 7 earlier days so far.")
        let none = InRange.calm(minutes: nil, previous: [5, 5, 5, 5, 5, 5, 5])
        #expect(none.state == .none)
        #expect(none.normal == .none)
        #expect(none.scale == nil)
        #expect(none.explanation.text == "Not enough clean readings this day.")
    }

    @Test func calmLearnsWhileTheStressBaselineIsLearning() {
        let verdict = InRange.calmBeforeBaseline(baselineDays: 3)
        #expect(verdict.state == .learning(soFar: 3, of: 7))
        #expect(verdict.normal == .none)
        #expect(verdict.scale == nil)
        #expect(
            verdict.explanation.text
                == "Learning your normal: your calm baseline needs 7 earlier days with at least 10 clean readings each; Vesel has 3. High-stress minutes, and then your usual for them, follow once it is ready."
        )
    }
}
