import Foundation
import Testing
import VeselCore

struct StressTests {
    /// 2026-10-26 10:00 in Berlin.
    let tenOClock = "2026-10-26T09:00:00Z"
    let baseline = StressBaseline(baseline: 2.72, floor: 2.0, days: 7, windows: 70)

    func windows(_ sessions: [PPISession], heartRates: [HeartRateSample] = [], limit: Double? = nil) -> (windows: [StressWindow], counts: StressCounts) {
        Stress.windows(sessions: sessions, heartRates: heartRates, activityHeartRate: limit)
    }

    @Test func aReadingIsTheRMSSDOfItsCleanBeats() throws {
        // 30 beats alternating 1000 and 1040: 29 differences of 40, so RMSSD = √(1600) = 40 ms, ln 40 = 3.6889.
        let result = windows([session(alternating(30))])
        let window = try #require(result.windows.first)
        #expect(result.windows.count == 1)
        #expect(window.rmssd == 40)
        #expect(abs(window.value - 3.688879) < 1e-5)
        #expect(window.intervals == 30)
        #expect(window.hour == 10)
        #expect(abs(window.seconds - 30.6) < 1e-6)
        #expect(result.counts.windows == 1)
    }

    @Test func aReadingNeedsThirtyCleanBeats() {
        let result = windows([session(alternating(29))])
        #expect(result.windows.isEmpty)
        #expect(result.counts.tooFewIntervals == 1)
    }

    @Test func beatsTheBandFlaggedOrWithoutSkinContactAreLeftOutAndNeverFilledIn() throws {
        // 40 beats, ten flagged for movement (positions 5 to 14): 30 clean ones remain, and removing an even number
        // of alternating beats keeps every difference at 40.
        let flagged = Set(5...14)
        let result = windows([session(alternating(40), flagged: flagged)])
        #expect(result.windows.first?.rmssd == 40)
        #expect(result.windows.first?.intervals == 30)
        #expect(result.counts.cleaning.flagged == 10)
        // One more flagged beat leaves 29: no reading.
        #expect(windows([session(alternating(40), flagged: Set(5...15))]).windows.isEmpty)
        // Beats without skin contact count the same way.
        let noSkin = windows([session(alternating(40), noSkin: Set(0..<10))])
        #expect(noSkin.windows.first?.intervals == 30)
        #expect(noSkin.counts.cleaning.flagged == 10)
        #expect(windows([session(alternating(40), noSkin: Set(0..<11))]).windows.isEmpty)
    }

    @Test func artefactsAreRemovedBeforeTheMaths() {
        // A 2500 ms beat (out of range) and a 1500 ms beat (a 50 % jump from 1000) would blow RMSSD up if kept.
        var intervals = alternating(30)
        intervals.insert(2500, at: 10)
        intervals.insert(1500, at: 20)
        let result = windows([session(intervals)])
        #expect(result.windows.first?.rmssd == 40)
        #expect(result.counts.cleaning.outOfRange == 1)
        #expect(result.counts.cleaning.jumps == 1)
    }

    @Test func aLongSessionIsCutIntoSixtySecondReadings() {
        // 150 beats of 1000/1040 last 153 s. Beats 1–58 end before 60 s, 59–117 before 120 s, 118–150 after: 58, 59 and 33 beats.
        let result = windows([session(alternating(150))])
        #expect(result.windows.map(\.intervals) == [58, 59, 33])
        #expect(result.windows.map(\.seconds) == [60, 60, 33])
        #expect(result.windows.allSatisfy { $0.rmssd == 40 })
    }

    @Test func nightReadingsAreNotStress() {
        let result = windows([session(alternating(30), at: "2026-10-26T02:00:00Z")])
        #expect(result.windows.isEmpty)
        #expect(result.counts.outsideDaytime == 1)
        // 06:00 local is daytime, 05:59 is not, 22:00 is not.
        #expect(windows([session(alternating(30), at: "2026-10-26T05:00:00Z")]).windows.count == 1)
        #expect(windows([session(alternating(30), at: "2026-10-26T04:59:00Z")]).windows.isEmpty)
        #expect(windows([session(alternating(30), at: "2026-10-26T20:59:00Z")]).windows.count == 1)
        #expect(windows([session(alternating(30), at: "2026-10-26T21:00:00Z")]).windows.isEmpty)
    }

    @Test func readingsDuringHighActivityAreSkipped() {
        // The window runs 09:00:00 to 09:00:30. A high-activity heart rate 90 s later is inside the 120 s margin; 5 minutes later is not.
        let during = HeartRateSample(time: at("2026-10-26T09:02:00Z"), bpm: 70, trigger: .highActivity)
        let result = windows([session(alternating(30))], heartRates: [during])
        #expect(result.windows.isEmpty)
        #expect(result.counts.duringActivity == 1)
        let later = HeartRateSample(time: at("2026-10-26T09:05:00Z"), bpm: 70, trigger: .highActivity)
        #expect(windows([session(alternating(30))], heartRates: [later]).windows.count == 1)
    }

    @Test func aHeartRateAboveRestingPlusFortyPercentOfTheReserveIsExercise() {
        // The limit is passed in: resting 55, max 185, reserve 130, 55 + 0.4 × 130 = 107.
        let limit = 55 + StressThresholds.activityReserveShare * 130
        #expect(limit == 107)
        let at107 = HeartRateSample(time: at("2026-10-26T09:00:10Z"), bpm: 107, trigger: .timed)
        let at108 = HeartRateSample(time: at("2026-10-26T09:00:10Z"), bpm: 108, trigger: .timed)
        #expect(windows([session(alternating(30))], heartRates: [at107], limit: limit).windows.count == 1)
        #expect(windows([session(alternating(30))], heartRates: [at108], limit: limit).windows.isEmpty)
        #expect(windows([session(alternating(30))], heartRates: [at108], limit: nil).windows.count == 1)
    }

    @Test func highMinutesAddUpEachHighReadingsGapCappedAtFifteenMinutes() {
        func window(_ seconds: Double, ln: Double) -> StressWindow {
            StressWindow(start: at("2026-10-26T09:00:00Z").addingTimeInterval(seconds), seconds: 60, intervals: 40, rmssd: exp(ln), hour: 10)
        }
        // High at 0 s (gap 60 s), high at 60 s (gap 540 s), high at 600 s (gap 1800 s, capped at 900), calm at 2400 s,
        // high at 3000 s (the last: its own 60 s). 60 + 540 + 900 + 60 = 1560 s = 26 minutes.
        let list = [window(0, ln: 2.0), window(60, ln: 2.0), window(600, ln: 2.0), window(2400, ln: 2.72), window(3000, ln: 2.0)]
        let result = Stress.highMinutes(of: list, baseline: baseline)
        #expect(result.minutes == 26)
        #expect(result.readings == 4)
    }

    @Test func theBusiestTwoHoursCountHighMinutesCutAtTheSpansEnd() throws {
        func window(_ seconds: Double, ln: Double) -> StressWindow {
            StressWindow(start: at("2026-10-26T09:00:00Z").addingTimeInterval(seconds), seconds: 60, intervals: 40, rmssd: exp(ln), hour: 10)
        }
        // High every 10 minutes for 3 hours (19 readings, each counting 600 s, the last 60 s). The 2 hours from the
        // first hold readings at 0…6600 s: 12 × 600 s = 120 minutes. Any later start holds less (the last reading counts 60 s).
        let steady = (0...18).map { window(Double($0 * 600), ln: 2.0) }
        let best = try #require(Stress.busiestSpan(of: steady, baseline: baseline))
        #expect(best.minutes == 120)
        #expect(best.start == at("2026-10-26T09:00:00Z"))
        // High at 0 s (gap capped at 15 min), at 6900 s (gap 300 s, 5 min, inside), at 7200 s (just outside the span from 0).
        let edge = [window(0, ln: 2.0), window(6900, ln: 2.0), window(7200, ln: 2.0)]
        let edgeBest = try #require(Stress.busiestSpan(of: edge, baseline: baseline))
        // From 0: 15 + 5 = 20 min. From 6900: 5 + 1 = 6 min.
        #expect(edgeBest.minutes == 20)
        #expect(Stress.busiestSpan(of: [window(0, ln: 2.72)], baseline: baseline) == nil)
    }

    @Test func aDayStoresItsReadingsAndHourlyLevelsOnceTheBaselineIsReady() throws {
        func window(_ hour: Int, _ minute: Int, ln: Double) -> StressWindow {
            StressWindow(
                start: at("2026-10-26T08:00:00Z").addingTimeInterval(Double((hour - 9) * 3600 + minute * 60)), seconds: 60, intervals: 40, rmssd: exp(ln),
                hour: hour)
        }
        // Hour 10: levels 50 and 100 (the highest counts). Hour 14: level 0.
        let list = [window(10, 0, ln: 2.36), window(10, 30, ln: 2.0), window(14, 0, ln: 2.72)]
        var counts = StressCounts()
        counts.sessions = 3
        counts.windows = 3
        let metrics = Stress.metrics(day: day("2026-10-26"), windows: list, counts: counts, baseline: .ready(baseline), computedAt: at("2026-10-26T12:00:00Z"))
        let byKey = Dictionary(uniqueKeysWithValues: metrics.map { ("\($0.kind)/\($0.hour ?? -1)", $0) })
        #expect(
            Set(byKey.keys) == [
                "stress.readings/-1", "stress.hourly/10", "stress.hourly/14", "stress.highMinutes/-1", "stress.busiestSpan/-1", "stress.now/-1",
            ])
        #expect(byKey["stress.readings/-1"]?.value == 3)
        #expect(abs((byKey["stress.hourly/10"]?.value ?? 0) - 100) < 1e-9)
        #expect(byKey["stress.hourly/14"]?.value == 0)
        #expect(byKey["stress.hourly/10"]?.explanation.inputs.first { $0.name == "readings" }?.value == 2)
        // One high reading (hour 10, level 100): gap to the next reading is 5 hours, capped at 15 minutes.
        #expect(byKey["stress.highMinutes/-1"]?.value == 15)
        let now = try #require(byKey["stress.now/-1"])
        #expect(now.value == 0)
        #expect(now.explanation.method == "stress")
        #expect(now.explanation.version == 2)
        let busiest = try #require(byKey["stress.busiestSpan/-1"].flatMap(StressSpan.init))
        #expect(busiest.minutes == 15)
        #expect(busiest.start == at("2026-10-26T09:30:00Z"))
        #expect(busiest.end == at("2026-10-26T11:30:00Z"))
        let readings = try #require(byKey["stress.readings/-1"])
        #expect(readings.explanation.inputs.first { $0.name == "baselineDays" }?.value == 7)
        #expect(readings.explanation.inputs.first { $0.name == "baseline" }?.value == 2.72)
        #expect(readings.explanation.inputs.first { $0.name == "floor" }?.value == 2.0)
        #expect(readings.explanation.inputs.first { $0.name == "baselineReadings" }?.value == 70)
        #expect(metrics.allSatisfy { !$0.explanation.text.isEmpty })
    }

    @Test func whileLearningOnlyTheReadingsCountIsStoredWithWhatWasCleaned() throws {
        let result = windows([session(alternating(40), flagged: Set(5...14))])
        let metrics = Stress.metrics(
            day: day("2026-10-26"), windows: result.windows, counts: result.counts, baseline: .learning(days: 4), computedAt: at("2026-10-26T12:00:00Z"))
        #expect(metrics.map(\.kind) == ["stress.readings"])
        let readings = try #require(metrics.first)
        #expect(readings.value == 1)
        #expect(readings.explanation.inputs.first { $0.name == "flagged" }?.value == 10)
        #expect(readings.explanation.inputs.first { $0.name == "baselineDays" }?.value == 4)
        #expect(readings.explanation.inputs.contains { $0.name == "baseline" } == false)
        #expect(readings.explanation.text.contains("Vesel has 4"))
    }

    @Test func nowIsTheLatestReadingForThirtyMinutes() throws {
        let metric = ComputedMetric(
            kind: MetricKind.stressNow, day: day("2026-10-26"), hour: nil, value: 40, unit: "of 100",
            explanation: Explanation(
                method: "stress", version: 1, inputs: [.init(name: "windowStart", value: at("2026-10-26T09:00:00Z").timeIntervalSince1970, unit: "unix s")],
                text: "x"),
            computedAt: at("2026-10-26T09:10:00Z")
        )
        let now = try #require(StressNow(metric))
        #expect(now.band == .moderate)
        #expect(now.sentence == "Moderately stressed now.")
        #expect(now.isRecent(at: at("2026-10-26T09:29:59Z")))
        #expect(!now.isRecent(at: at("2026-10-26T09:30:00Z")))
        #expect(!now.isRecent(at: at("2026-10-26T08:59:00Z")))
    }

    @Test func aPastDaySaysItsHighStressMinutes() {
        #expect(StressDay.sentence(highMinutes: nil) == nil)
        #expect(StressDay.sentence(highMinutes: 0) == "No high stress.")
        #expect(StressDay.sentence(highMinutes: 0.4) == "No high stress.")
        #expect(StressDay.sentence(highMinutes: 45) == "45 m of high stress.")
        #expect(StressDay.sentence(highMinutes: 80) == "1 h 20 m of high stress.")
        #expect(StressDay.sentence(highMinutes: 60) == "1 h of high stress.")
        #expect(StressDay.sentence(highMinutes: 59.6) == "1 h of high stress.")
        #expect(StressDay.sentence(highMinutes: 120) == "2 h of high stress.")
        #expect(StressDay.sentence(highMinutes: 125) == "2 h 05 m of high stress.")
        #expect(StressDay.ringText(highMinutes: nil) == "—")
        #expect(StressDay.ringText(highMinutes: 0) == "0 m")
        #expect(StressDay.ringText(highMinutes: 45) == "45 m")
    }
}
