import Foundation
import Testing
import VeselCore

struct ScrubLookupTests {
    /// 2026-10-25 21:30Z to 05:30Z: phases at 1800 s (deep), 0 s (light), 3600 s (rem), given out of order.
    func night(_ phases: [SleepPhase]) -> SleepNight {
        SleepNight(night: day("2026-10-26"), start: at("2026-10-25T21:30:00Z"), end: at("2026-10-26T05:30:00Z"), goalMinutes: nil, phases: phases)
    }

    let phases = [
        SleepPhase(secondsFromStart: 3600, state: .rem),
        SleepPhase(secondsFromStart: 0, state: .light),
        SleepPhase(secondsFromStart: 1800, state: .deep),
    ]

    @Test func stateFollowsTheSortedPhasesAndIsNilOutsideTheNight() {
        let night = night(phases)
        #expect(night.state(at: at("2026-10-25T21:30:00Z")) == .light)
        #expect(night.state(at: at("2026-10-25T21:59:59Z")) == .light)
        #expect(night.state(at: at("2026-10-25T22:00:00Z")) == .deep)
        #expect(night.state(at: at("2026-10-25T22:30:00Z")) == .rem)
        #expect(night.state(at: at("2026-10-26T05:30:00Z")) == .rem)
        #expect(night.state(at: at("2026-10-25T21:29:59Z")) == nil)
        #expect(night.state(at: at("2026-10-26T05:30:01Z")) == nil)
    }

    @Test func beforeTheFirstPhaseIsWake() {
        let late = night([SleepPhase(secondsFromStart: 600, state: .deep)])
        #expect(late.state(at: at("2026-10-25T21:39:59Z")) == .wake)
        #expect(late.state(at: at("2026-10-25T21:40:00Z")) == .deep)
    }

    @Test func aNegativeOffsetCountsFromTheStart() {
        let early = night([SleepPhase(secondsFromStart: -300, state: .rem), SleepPhase(secondsFromStart: 600, state: .light)])
        #expect(early.state(at: at("2026-10-25T21:30:00Z")) == .rem)
        #expect(early.state(at: at("2026-10-25T21:40:00Z")) == .light)
    }

    @Test func twoNegativeOffsetsKeepSleepSummarysOrder() {
        let early = night([SleepPhase(secondsFromStart: -100, state: .light), SleepPhase(secondsFromStart: -300, state: .rem)])
        let summary = SleepSummary(early, heartRates: [])
        #expect(summary.stageSeconds[.light] == 8 * 3600)
        #expect(early.state(at: at("2026-10-25T21:30:00Z")) == .light)
        #expect(early.state(at: at("2026-10-26T03:00:00Z")) == .light)
    }

    @Test func noPhasesIsUnknown() {
        #expect(night([]).state(at: at("2026-10-26T01:00:00Z")) == .unknown)
    }

    func sample(_ iso: String, _ bpm: Int) -> HeartRateSample {
        HeartRateSample(time: at(iso), bpm: bpm, trigger: .timed)
    }

    @Test func nearestWithinHalfTheGapPicksTheCloserNeighbour() {
        let samples = [sample("2026-10-26T01:00:00Z", 50), sample("2026-10-26T01:20:00Z", 60)]
        let limit = HeartRateSample.lineGap / 2
        #expect(samples.nearest(to: at("2026-10-26T01:07:30Z"), within: limit)?.bpm == 50)
        #expect(samples.nearest(to: at("2026-10-26T01:07:31Z"), within: limit) == nil)
        #expect(samples.nearest(to: at("2026-10-26T01:12:30Z"), within: limit)?.bpm == 60)
        #expect(samples.nearest(to: at("2026-10-26T01:12:29Z"), within: limit) == nil)
        let close = [sample("2026-10-26T01:00:00Z", 50), sample("2026-10-26T01:10:00Z", 60)]
        #expect(close.nearest(to: at("2026-10-26T01:04:00Z"), within: 450)?.bpm == 50)
        #expect(close.nearest(to: at("2026-10-26T01:06:00Z"), within: 450)?.bpm == 60)
        #expect([HeartRateSample]().nearest(to: at("2026-10-26T01:06:00Z"), within: 450) == nil)
    }
}
