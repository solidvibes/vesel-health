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

    @Test func theSentenceFollowsPolarsStatus() {
        let sentences = (1...6).map { RecoverySentence.make(status: status($0), contributors: [], asleepMinutes: nil)?.sentence }
        #expect(
            sentences == [
                "Recovery is low.", "Recovery is low.", "Recovery is lower than usual.",
                "Recovery is OK.", "Recovery is good.", "You're well recovered.",
            ])
    }

    @Test func theWhyNamesTheBiggestDeparture() throws {
        // HRV 26 is 2 SDs below its usual 42: 16 ms is 38 % of 42. Resting heart rate 56 is 1 SD above 54.
        let all = readings([.hrv: 26, .restingHeartRate: 56], history: earlier)
        let headline = try #require(RecoverySentence.make(status: status(3), contributors: all, asleepMinutes: 460))
        #expect(headline.sentence == "Recovery is lower than usual.")
        #expect(headline.why == "HRV 38 % below your usual; 7 h 40 m asleep.")
        #expect(headline.explanation.method == "recoverySentence")
        #expect(headline.explanation.version == 1)
        #expect(headline.explanation.inputs.first { $0.name == "rule" }?.value == 4)
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

    @Test func skinTemperatureInTheWhyFollowsTheUnits() throws {
        // Usual mean 34.2 °C; 34.7 is 0.5 °C above, which is 0.9 °F.
        let skin = readings([.skinTemperature: 34.7], history: history(.skinTemperature, [34.0, 34.2, 34.4, 34.2, 34.0, 34.4, 34.2]))
        let metric = try #require(RecoverySentence.make(status: status(4), contributors: skin, asleepMinutes: nil, units: .metric))
        let us = try #require(RecoverySentence.make(status: status(4), contributors: skin, asleepMinutes: nil, units: .us))
        #expect(metric.why == "Skin temperature 0.5 °C above your usual.")
        #expect(us.why == "Skin temperature 0.9 °F above your usual.")
        #expect(us.explanation == metric.explanation)
    }

    @Test func theExplanationNamesNoRuleNumber() throws {
        let ending = "The second line names the contributor furthest from your usual (more than 1 standard deviation away), then your time asleep."
        let scored = try #require(RecoverySentence.make(status: status(5), contributors: [], asleepMinutes: 460))
        #expect(scored.explanation.text == "The sentence follows Polar's Nightly Recharge: 5 of 6 (good) reads \"Recovery is good.\" \(ending)")
        let unscored = try #require(RecoverySentence.make(status: nil, contributors: [], asleepMinutes: 460))
        #expect(
            unscored.explanation.text
                == "There is a night of sleep but no Nightly Recharge yet, so the sentence says Polar hasn't scored your recovery. \(ending)")
        #expect(!scored.explanation.text.contains("Rule"))
    }

    @Test func theLargestSpreadWinsAndSleepIsWrittenInTime() throws {
        // HRV 36 is 0.75 SD below usual; resting heart rate 59 is 2.5 SDs above it.
        let all = readings([.hrv: 36, .restingHeartRate: 59], history: earlier)
        let headline = try #require(RecoverySentence.make(status: status(2), contributors: all, asleepMinutes: 365))
        #expect(headline.why == "Resting heart rate 5 bpm above your usual; 6 h 05 m asleep.")
    }

    @Test func whenEverythingIsUsualItSaysSo() throws {
        let all = readings([.hrv: 44, .restingHeartRate: 54], history: earlier)
        let headline = try #require(RecoverySentence.make(status: status(5), contributors: all, asleepMinutes: 460))
        #expect(headline.why == "Everything is within your usual range; 7 h 40 m asleep.")
    }

    @Test func whileLearningItSaysHowFarAlong() throws {
        let all = readings([.hrv: 44], history: history(.hrv, [40, 42, 44]))
        let headline = try #require(RecoverySentence.make(status: status(4), contributors: all, asleepMinutes: 480))
        #expect(headline.why == "Your usual range appears after 7 nights · 3 of 7; 8 h asleep.")
    }

    @Test func withoutARecoveryStatusItStillSpeaksAboutSleep() throws {
        let headline = try #require(RecoverySentence.make(status: nil, contributors: [], asleepMinutes: 460))
        #expect(headline.sentence == "Polar hasn't scored your recovery yet.")
        #expect(headline.why == "7 h 40 m asleep.")
        #expect(headline.explanation.inputs.first { $0.name == "rule" }?.value == 6)
        #expect(RecoverySentence.make(status: nil, contributors: [], asleepMinutes: nil) == nil)
    }
}
