import Foundation
import Testing
import VeselCore

struct RecoveryContributorsTests {
    let computedAt = at("2026-10-26T06:00:00Z")

    @Test func takesTheValuesFromPolarsNightlyMeans() {
        let recharge = NightlyRecharge(
            night: day("2026-10-26"),
            meanNightlyRecoveryRRI: 1000,
            meanNightlyRecoveryRMSSD: 40,
            meanNightlyRecoveryRespirationInterval: 4000
        )
        let summary = SleepSummary(sampleNight(), heartRates: [])
        let skin = [
            SkinTemperatureSample(time: at("2026-10-25T20:00:00Z"), celsius: 30.0),
            SkinTemperatureSample(time: at("2026-10-26T00:00:00Z"), celsius: 34.0),
            SkinTemperatureSample(time: at("2026-10-26T02:00:00Z"), celsius: 34.4),
            SkinTemperatureSample(time: at("2026-10-26T04:00:00Z"), celsius: 34.2),
            SkinTemperatureSample(time: at("2026-10-26T09:00:00Z"), celsius: 36.0),
        ]
        let values = RecoveryContributors.values(recharge: recharge, summary: summary, skinTemperatures: skin).values
        #expect(values[.hrv] == 40)
        #expect(values[.restingHeartRate] == 60)
        #expect(values[.breathing] == 15)
        #expect(values[.sleep] == 460)
        #expect(abs((values[.skinTemperature] ?? 0) - 34.2) < 1e-9)
    }

    @Test func missingInputsLeaveOutTheirContributor() {
        let values = RecoveryContributors.values(recharge: nil, summary: nil, skinTemperatures: []).values
        #expect(values.isEmpty)
    }

    @Test func sevenEarlierNightsGiveARangeAndAVerdict() throws {
        // Earlier HRV 30 34 38 42 46 50 54: mean 42, squares 144 64 16 0 16 64 144 = 448, ÷ 7 = 64, SD 8.
        let earlier = history(.hrv, [30, 34, 38, 42, 46, 50, 54])
        let low = try #require(readings([.hrv: 26], history: earlier).first)
        let wellBelow = try #require(readings([.hrv: 24], history: earlier).first)
        let usual = try #require(readings([.hrv: 49], history: earlier).first)

        #expect(low.range == PersonalRange(mean: 42, sd: 8, nights: 7))
        #expect(low.usualText() == "34 ms–50 ms")
        #expect(low.difference == -16)
        #expect(low.spreads == -2)
        #expect(low.verdict == .lower)
        #expect(wellBelow.verdict == .wellBelow)
        #expect(usual.verdict == .usual)
        #expect(low.valueText() == "26 ms")
    }

    @Test func sixEarlierNightsAreStillLearning() throws {
        let earlier = history(.hrv, [30, 34, 38, 42, 46, 50])
        let reading = try #require(readings([.hrv: 26], history: earlier).first)
        #expect(reading.range == nil)
        #expect(reading.nights == 6)
        #expect(reading.verdict == .learning(nights: 6))
        #expect(reading.difference == nil)
        #expect(reading.usualText() == nil)
        #expect(reading.explanation.text.contains("needs 7 earlier nights"))
    }

    @Test func aNightMoreThan28DaysBackIsNotInTheRange() throws {
        var earlier = history(.hrv, [30, 34, 38, 42, 46, 50])
        earlier[day("2026-09-27")] = [.hrv: 100]
        let reading = try #require(readings([.hrv: 26], history: earlier).first)
        #expect(reading.nights == 6)
    }

    @Test func restingHeartRateAndBreathingShowTheirMeasuredInterval() throws {
        let both = RecoveryContributors.values(
            recharge: NightlyRecharge(night: day("2026-10-26"), meanNightlyRecoveryRRI: 1100, meanNightlyRecoveryRespirationInterval: 3900),
            summary: nil, skinTemperatures: []
        )
        let metrics = RecoveryContributors.metrics(night: day("2026-10-26"), values: both, history: [:], computedAt: computedAt)
        let resting = try #require(metrics.first { $0.kind == Contributor.restingHeartRate.kind })
        let breathing = try #require(metrics.first { $0.kind == Contributor.breathing.kind })
        #expect(abs(resting.value - 54.5454) < 1e-3)
        #expect(resting.explanation.inputs.first?.name == "meanBeatInterval")
        #expect(resting.explanation.inputs.first?.value == 1100)
        #expect(resting.explanation.text.contains("54.5 bpm"))
        #expect(abs(breathing.value - 15.3846) < 1e-3)
        #expect(breathing.explanation.text.contains("15.4 breaths/min"))
        #expect(metrics.allSatisfy { $0.explanation.method == "recovery" && $0.explanation.version == 2 })
    }

    @Test func skinTemperatureShowsAsADifferenceFromUsual() throws {
        let earlier = history(.skinTemperature, [34.0, 34.2, 34.4, 34.2, 34.0, 34.4, 34.2])
        let reading = try #require(readings([.skinTemperature: 34.7], history: earlier).first)
        // Mean of the seven is 34.2.
        #expect(abs((reading.difference ?? 0) - 0.5) < 1e-9)
        #expect(reading.differenceText() == "+0.5 °C")
        #expect(reading.explanation.text.contains("difference from your usual mean of 34.2 °C"))
        // US: 0.5 °C × 9 ÷ 5 = 0.9 °F; 34.7 °C = 94.46 °F. The stored explanation stays metric.
        #expect(reading.differenceText(units: .us) == "+0.9 °F")
        #expect(reading.valueText(units: .us) == "94.5 °F")
        #expect(reading.valueText() == "34.7 °C")
    }

    @Test func polarsRecoveryStatusIsStoredAsGiven() throws {
        func status(_ indicator: Int?, _ sub: Int?) -> RecoveryStatus? {
            RecoveryStatus(NightlyRecharge(night: day("2026-10-26"), recoveryIndicator: indicator, recoveryIndicatorSubLevel: sub))
        }
        let ok = try #require(status(4, 50))
        #expect(ok.word == "OK")
        #expect(abs(ok.fill - 3.5 / 6) < 1e-9)
        #expect(status(1, 0)?.fill == 0)
        #expect(status(6, 100)?.fill == 1)
        #expect(status(2, nil)?.word == "poor")
        #expect(status(3, 40)?.word == "compromised")
        #expect(status(nil, 50) == nil)
        #expect(status(7, 0) == nil)

        let metric = ok.metric(computedAt: computedAt)
        #expect(RecoveryStatus(metric) == ok)
        #expect(metric.explanation.version == 2)
        #expect(metric.explanation.text == "Polar's Nightly Recharge says OK (4 of 6).")
    }

    @Test func sleepIsJudgedAgainstTheSleepLinesNormal() throws {
        let earlier = history(.sleep, [420, 480, 450, 510, 440, 470, 460])
        let range = try #require(PersonalRange(previous: [420, 480, 450, 510, 440, 470, 460]))
        func reading(_ spreads: Double) throws -> ContributorReading {
            try #require(readings([.sleep: range.mean + spreads * range.sd], history: earlier).first)
        }
        // Words, verdicts and the Sleep line agree: normal is 1 SD under to 2 SD over the mean.
        let cases: [(Double, RangeVerdict, String, LineState)] = [
            (1.5, .usual, "usual", .inside),
            (-0.9, .usual, "usual", .inside),
            (2.5, .wellAbove, "longer than usual", .above),
            (-1.5, .lower, "shorter than usual", .below),
            (-2.5, .wellBelow, "much shorter than usual", .below),
        ]
        for (spreads, verdict, word, state) in cases {
            let sleep = try reading(spreads)
            #expect(sleep.verdict == verdict)
            #expect(sleep.verdictWord == word)
            #expect(InRange.sleep(sleep).state == state)
        }
        #expect(try reading(1.5).spreads == 0)
        #expect(abs(try #require(reading(3).spreads) - 2) < 1e-9)
        #expect(abs(try #require(reading(-2.5).spreads) + 2.5) < 1e-9)
        #expect(try reading(1.5).explanation.text.contains("Your normal is from 1 standard deviation under to 2 over the mean of your previous 7 nights"))
        #expect(try reading(1.5).explanation.version == 2)
    }

    @Test func otherContributorsKeepOneSDAndTheirWords() throws {
        let earlier = history(.hrv, [30, 34, 38, 42, 46, 50, 42])
        let range = try #require(PersonalRange(previous: [30, 34, 38, 42, 46, 50, 42]))
        let hrv = try #require(readings([.hrv: range.mean + 1.5 * range.sd], history: earlier).first)
        #expect(hrv.verdict == .higher)
        #expect(hrv.verdictWord == "higher than usual")
        #expect(hrv.explanation.text.contains("mean ± 1 standard deviation"))
    }
}
