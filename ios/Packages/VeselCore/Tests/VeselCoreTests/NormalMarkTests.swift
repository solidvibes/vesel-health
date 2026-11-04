import Testing
import VeselCore

struct NormalMarkTests {
    @Test func theBetterSideIsGreenAtAnyDistanceAndTheOtherSideIsOffThenFar() {
        let cases: [(RangeVerdict, NormalMark.Better, NormalMark?)] = [
            (.usual, .higher, .inside), (.usual, .lower, .inside), (.usual, .neither, .inside),
            (.higher, .higher, .better(.above)), (.wellAbove, .higher, .better(.above)),
            (.lower, .higher, .off(.below)), (.wellBelow, .higher, .far(.below)),
            (.lower, .lower, .better(.below)), (.wellBelow, .lower, .better(.below)),
            (.higher, .lower, .off(.above)), (.wellAbove, .lower, .far(.above)),
            (.higher, .neither, .off(.above)), (.wellAbove, .neither, .far(.above)),
            (.lower, .neither, .off(.below)), (.wellBelow, .neither, .far(.below)),
            (.learning(nights: 3), .higher, nil), (.learning(nights: 0), .neither, nil),
        ]
        for (verdict, better, expected) in cases {
            #expect(NormalMark(verdict: verdict, better: better) == expected, "\(verdict) \(better)")
        }
    }

    @Test func eachContributorHasItsBetterSide() {
        #expect(Contributor.hrv.better == .higher)
        #expect(Contributor.sleep.better == .higher)
        #expect(Contributor.restingHeartRate.better == .lower)
        #expect(Contributor.breathing.better == .neither)
        #expect(Contributor.skinTemperature.better == .neither)
    }

    @Test func aContributorReadingMarksItselfAgainstItsOwnNormal() throws {
        let values: [Double] = [30, 34, 38, 42, 46, 50, 42]
        let range = try #require(PersonalRange(previous: values))
        func mark(_ contributor: Contributor, _ spreads: Double) throws -> NormalMark? {
            try #require(readings([contributor: range.mean + spreads * range.sd], history: history(contributor, values)).first).mark
        }
        #expect(try mark(.hrv, 0.5) == .inside)
        #expect(try mark(.hrv, 1.5) == .better(.above))
        #expect(try mark(.hrv, -1.5) == .off(.below))
        #expect(try mark(.hrv, -2.5) == .far(.below))
        #expect(try mark(.restingHeartRate, -2.5) == .better(.below))
        #expect(try mark(.restingHeartRate, 1.5) == .off(.above))
        #expect(try mark(.restingHeartRate, 2.5) == .far(.above))
        #expect(try mark(.breathing, 1.5) == .off(.above))
        #expect(try mark(.skinTemperature, -2.5) == .far(.below))
    }

    @Test func sleepAboveItsNormalIsOffNeverBetterOrFar() throws {
        let values: [Double] = [420, 480, 450, 510, 440, 470, 460]
        let range = try #require(PersonalRange(previous: values))
        func mark(_ spreads: Double) throws -> NormalMark? {
            try #require(readings([.sleep: range.mean + spreads * range.sd], history: history(.sleep, values)).first).mark
        }
        #expect(try mark(1.5) == .inside)
        #expect(try mark(2.5) == .off(.above))
        #expect(try mark(6) == .off(.above))
        #expect(try mark(-1.5) == .off(.below))
        #expect(try mark(-2.5) == .far(.below))
    }

    @Test func aReadingWithTooFewEarlierNightsHasNoMark() throws {
        let reading = try #require(readings([.hrv: 40], history: history(.hrv, [40, 41, 42])).first)
        #expect(reading.mark == nil)
    }

    @Test func recoveryIsInsideFromFourOffAtThreeAndFarBelow() {
        let marks = (1...6).map { RecoveryStatus(NightlyRecharge(night: day("2026-10-26"), recoveryIndicator: $0, recoveryIndicatorSubLevel: 50))?.mark }
        #expect(marks == [.far(.below), .far(.below), .off(.below), .inside, .inside, .inside])
    }

    @Test func eachMarkHasItsSymbolAndWords() {
        #expect(NormalMark.inside.symbol == "checkmark")
        #expect(NormalMark.inside.words == "inside your normal")
        #expect(NormalMark.better(.above).symbol == "arrow.up")
        #expect(NormalMark.better(.above).words == "above your normal, the good side")
        #expect(NormalMark.better(.below).symbol == "arrow.down")
        #expect(NormalMark.better(.below).words == "below your normal, the good side")
        #expect(NormalMark.off(.above).words == "above your normal")
        #expect(NormalMark.off(.below).symbol == "arrow.down")
        #expect(NormalMark.far(.above).symbol == "exclamationmark.2")
        #expect(NormalMark.far(.above).words == "well above your normal")
        #expect(NormalMark.far(.below).words == "well below your normal")
        #expect(!NormalMark.inside.isOutside)
        #expect(NormalMark.far(.below).isOutside)
    }

    @Test func theScaleSitsTheNormalInTheMiddleThirdAndClampsAtTheEnds() {
        let scale = NormalScale.scale(value: 62, low: 34, high: 52)
        #expect(scale.normalFrom == 1.0 / 3)
        #expect(abs(scale.normalTo - 2.0 / 3) < 1e-9)
        #expect(scale.dot > scale.normalTo)
        #expect(NormalScale.scale(value: 500, low: 34, high: 52).dot == 1)
        #expect(NormalScale.scale(value: -5, low: 34, high: 52).dot == 0)
        #expect(NormalScale.scale(value: 43, low: 34, high: 52).dot == 0.5)
    }

    @Test func theTrackStopsAtTheFloorAndTheCeiling() {
        let duration = NormalScale.scale(value: 300, low: 100, high: 500, floor: 0)
        #expect(duration.normalFrom == 100.0 / 900)
        let percent = NormalScale.scale(value: 99, low: 90, high: 96, floor: 0, ceiling: 100)
        #expect(percent.normalTo == (96.0 - 84) / (100 - 84))
        #expect(percent.dot == (99.0 - 84) / (100 - 84))
    }

    @Test func aNormalWithNoWidthStillHasATrack() {
        let scale = NormalScale.scale(value: 50, low: 50, high: 50)
        #expect(scale.dot == 0.5)
        #expect(scale.normalFrom <= scale.normalTo)
    }
}
