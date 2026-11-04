import Foundation
import Testing
@testable import VeselCore

struct RecoverySentenceTests {
    func status(_ indicator: Int) -> RecoveryStatus {
        RecoveryStatus(NightlyRecharge(night: day("2026-10-26"), recoveryIndicator: indicator, recoveryIndicatorSubLevel: 0))!
    }

    /// Earlier HRV: mean 42, SD 8. Earlier resting heart rate: mean 54, SD 2.
    var earlier: [DayKey: [Contributor: Double]] {
        var merged = history(.hrv, [30, 34, 38, 42, 46, 50, 54])
        let resting = history(.restingHeartRate, [51, 52, 53, 54, 55, 56, 57])
        for (key, value) in resting { merged[key, default: [:]].merge(value) { $1 } }
        return merged
    }

    @Test func sleepOnlyNamesItselfOutsideItsNormal() throws {
        let values: [Double] = [420, 480, 450, 510, 440, 470, 460]
        let range = try #require(PersonalRange(previous: values))
        let sleepHistory = history(.sleep, values)
        // 1.5 SD over the mean is inside the sleep normal (1 SD under to 2 SD over): not a driver.
        let inside = readings([.sleep: range.mean + 1.5 * range.sd], history: sleepHistory)
        #expect(RecoverySentence.driver(inside) == nil)
        // 2.5 SD over is outside: named.
        let above = readings([.sleep: range.mean + 2.5 * range.sd], history: sleepHistory)
        #expect(RecoverySentence.driver(above)?.contributor == .sleep)
        // 1.5 SD under is outside, but a 2-SD HRV departure is further from usual.
        let mixed =
            readings([.sleep: range.mean - 1.5 * range.sd], history: sleepHistory)
            + readings([.hrv: 26], history: earlier)
        #expect(RecoverySentence.driver(mixed)?.contributor == .hrv)
    }

    @Test func theVerdictWordsAreShort() {
        #expect((1...6).map { status($0).verdict } == ["Low recovery", "Low recovery", "Lower than usual", "Recovery OK", "Good recovery", "Well recovered"])
    }

    @Test func theQuietLineShowsOnlyForALowNightWhereEveryMarkedRowIsInside() {
        // HRV mean 42, SD 8: 44 is inside, 26 is far below. Resting heart rate mean 54, SD 2: 54 inside, 49 is better.
        let inside = readings([.hrv: 44, .restingHeartRate: 54], history: earlier)
        let oneBetter = readings([.hrv: 44, .restingHeartRate: 49], history: earlier)
        let oneOff = readings([.hrv: 26, .restingHeartRate: 54], history: earlier)
        let learning = readings([.hrv: 44], history: history(.hrv, [40, 42, 44]))
        let line = "None of last night's readings stood out on its own; Polar weighs them together."
        for indicator in [3, 2, 1] {
            #expect(RecoverySentence.quietLine(status: status(indicator), contributors: inside) == line)
            #expect(RecoverySentence.quietLine(status: status(indicator), contributors: oneBetter) == nil)
            #expect(RecoverySentence.quietLine(status: status(indicator), contributors: oneOff) == nil)
            #expect(RecoverySentence.quietLine(status: status(indicator), contributors: learning) == nil)
        }
        #expect(RecoverySentence.quietLine(status: status(4), contributors: inside) == nil)
        #expect(RecoverySentence.quietLine(status: nil, contributors: inside) == nil)
        #expect(RecoverySentence.quietLine(status: status(3), contributors: []) == nil)
    }
}
