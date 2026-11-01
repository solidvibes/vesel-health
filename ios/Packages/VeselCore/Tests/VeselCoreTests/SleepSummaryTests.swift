import Foundation
import Testing
import VeselCore

struct SleepSummaryTests {
    func heartRate(_ iso: String, _ bpm: Int) -> HeartRateSample {
        HeartRateSample(time: at(iso), bpm: bpm, trigger: .timed)
    }

    @Test func addsUpThePhases() {
        let summary = SleepSummary(sampleNight(), heartRates: [])
        #expect(summary.inBedSeconds == 28_800)
        #expect(summary.stageSeconds[.light] == 15_000)
        #expect(summary.stageSeconds[.deep] == 7_200)
        #expect(summary.stageSeconds[.rem] == 5_400)
        #expect(summary.stageSeconds[.wake] == 1_200)
        #expect(summary.asleepSeconds == 27_600)
    }

    @Test func efficiencyIsTimeAsleepOverTimeInBed() {
        let summary = SleepSummary(sampleNight(), heartRates: [])
        #expect(abs(summary.efficiency - 27_600.0 / 28_800.0) < 1e-9)
        #expect(abs(summary.efficiency - 0.958_333) < 1e-5)
    }

    @Test func lowestHeartRateCountsOnlyTheSleepWindowEndsIncluded() {
        let samples = [
            heartRate("2026-10-25T21:00:00Z", 40),
            heartRate("2026-10-25T21:30:00Z", 58),
            heartRate("2026-10-25T22:00:00Z", 55),
            heartRate("2026-10-26T01:30:00Z", 49),
            heartRate("2026-10-26T04:00:00Z", 52),
            heartRate("2026-10-26T05:30:00Z", 51),
            heartRate("2026-10-26T05:35:00Z", 45),
        ]
        #expect(SleepSummary(sampleNight(), heartRates: samples).lowestHeartRate == 49)
        #expect(SleepSummary(sampleNight(), heartRates: []).lowestHeartRate == nil)
    }

    @Test func aNightAcrossTheClockChangeIsNineRealHours() {
        // 22:30 CEST on 24 October to 06:30 CET on 25 October: the clocks go back at 03:00, so the wall clock says 8 h.
        let night = SleepNight(
            night: DayKey.night(endingAt: at("2026-10-25T05:30:00Z"), in: berlin),
            start: at("2026-10-24T20:30:00Z"),
            end: at("2026-10-25T05:30:00Z"),
            goalMinutes: 480,
            phases: [SleepPhase(secondsFromStart: 0, state: .light)]
        )
        let summary = SleepSummary(night, heartRates: [])
        #expect(night.night == day("2026-10-25"))
        #expect(summary.inBedSeconds == 32_400)
        #expect(summary.asleepSeconds == 32_400)
        #expect(summary.efficiency == 1)
    }

    @Test func timeBeforeTheFirstPhaseCountsAsAwake() {
        let night = SleepNight(
            night: day("2026-10-26"), start: at("2026-10-25T21:30:00Z"), end: at("2026-10-25T22:30:00Z"),
            goalMinutes: nil, phases: [SleepPhase(secondsFromStart: 600, state: .light)]
        )
        let summary = SleepSummary(night, heartRates: [])
        #expect(summary.stageSeconds[.wake] == 600)
        #expect(summary.asleepSeconds == 3_000)
    }

    @Test func everyNumberCarriesItsExplanation() {
        let metrics = SleepSummary(sampleNight(), heartRates: [HeartRateSample(time: at("2026-10-26T01:30:00Z"), bpm: 49, trigger: .timed)])
            .metrics(computedAt: at("2026-10-26T06:00:00Z"))
        let byKind = Dictionary(uniqueKeysWithValues: metrics.map { ($0.kind, $0) })
        #expect(byKind[MetricKind.sleepAsleep]?.value == 460)
        #expect(byKind[MetricKind.sleepInBed]?.value == 480)
        #expect(byKind[MetricKind.sleepStage(.deep)]?.value == 120)
        #expect(byKind[MetricKind.sleepStage(.light)]?.value == 250)
        #expect(byKind[MetricKind.sleepStage(.rem)]?.value == 90)
        #expect(byKind[MetricKind.sleepStage(.wake)]?.value == 20)
        #expect(byKind[MetricKind.sleepLowestHeartRate]?.value == 49)
        #expect(abs((byKind[MetricKind.sleepEfficiency]?.value ?? 0) - 95.8333) < 1e-3)
        #expect(
            metrics.allSatisfy { $0.day == day("2026-10-26") && $0.explanation.version == 1 && !$0.explanation.text.isEmpty && !$0.explanation.inputs.isEmpty })
    }

    @Test func durationsAreWrittenForPeople() {
        #expect(DurationText.hoursMinutes(minutes: 460) == "7 h 40 m")
        #expect(DurationText.hoursMinutes(minutes: 365) == "6 h 05 m")
        #expect(DurationText.hoursMinutes(minutes: 45) == "45 m")
        #expect(DurationText.hoursMinutes(minutes: 480) == "8 h")
    }
}
