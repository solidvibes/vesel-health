#if DEBUG
import Foundation
import VeselCore
import VeselStorage

/// Made-up snapshots for previews and the screenshot test. Not real data.
extension WidgetSnapshot {
    static func sampleStatus(indicator: Int, subLevel: Int, night: DayKey) -> RecoveryStatus {
        let metric = ComputedMetric(
            kind: MetricKind.recoveryStatus, day: night, hour: nil, value: 0, unit: "fraction",
            explanation: Explanation(
                method: RecoveryStatus.method, version: RecoveryStatus.version,
                inputs: [.init(name: "indicator", value: Double(indicator), unit: "of 6"), .init(name: "subLevel", value: Double(subLevel), unit: "of 100")],
                text: ""
            ),
            computedAt: .now
        )
        return RecoveryStatus(metric)!
    }

    static func sampleStress(level: Double, at now: Date) -> StressNow {
        StressNow(
            ComputedMetric(
                kind: MetricKind.stressNow, day: DayKey(now, in: .current), hour: nil, value: level, unit: "level",
                explanation: Explanation(
                    method: Stress.method, version: 2,
                    inputs: [.init(name: "windowStart", value: now.addingTimeInterval(-300).timeIntervalSince1970, unit: "s")], text: ""
                ),
                computedAt: now
            ))!
    }

    static func sampleHRV(night: DayKey, value: Double, nights: Int) -> ContributorReading {
        var inputs: [Explanation.Input] = [.init(name: "nights", value: Double(nights), unit: "nights")]
        if nights >= PersonalRange.minimumNights {
            inputs += [.init(name: "usualMean", value: 48, unit: "ms"), .init(name: "usualSD", value: 6, unit: "ms")]
        }
        return ContributorReading(
            ComputedMetric(
                kind: Contributor.hrv.kind, day: night, hour: nil, value: value, unit: "ms",
                explanation: Explanation(method: "recovery.hrv", version: 1, inputs: inputs, text: ""), computedAt: .now
            ))!
    }

    static func sampleSleep(night: DayKey, minutes: Double, nights: Int) -> ContributorReading {
        var inputs: [Explanation.Input] = [.init(name: "nights", value: Double(nights), unit: "nights")]
        if nights >= PersonalRange.minimumNights {
            inputs += [.init(name: "usualMean", value: 450, unit: "min"), .init(name: "usualSD", value: 40, unit: "min")]
        }
        return ContributorReading(
            ComputedMetric(
                kind: Contributor.sleep.kind, day: night, hour: nil, value: minutes, unit: "min",
                explanation: Explanation(method: "recovery.sleep", version: 1, inputs: inputs, text: ""), computedAt: .now
            ))!
    }

    static func sampleLines(status: RecoveryStatus, earlierNights: Int, asleepMinutes: Double = 425, highMinutes: Double = 12) -> DayLines {
        DayLines(
            recovery: InRange.recovery(status: status, earlierNights: earlierNights),
            sleep: InRange.sleep(sampleSleep(night: status.night, minutes: asleepMinutes, nights: earlierNights)),
            calm: InRange.calm(minutes: highMinutes, previous: Array(repeating: 10, count: min(earlierNights, 12))),
            indicator: status.indicator, asleepMinutes: asleepMinutes, highMinutes: highMinutes
        )
    }

    static func sampleReady(
        at now: Date, indicator: Int = 5, subLevel: Int = 40, syncedAgo: TimeInterval = 600, earlierNights: Int = 20, asleepMinutes: Double = 425,
        highMinutes: Double = 12, hrv: Double = 60, stressLevel: Double = 22
    ) -> WidgetSnapshot {
        let night = DayKey(now, in: .current)
        let status = sampleStatus(indicator: indicator, subLevel: subLevel, night: night)
        let lines = sampleLines(status: status, earlierNights: earlierNights, asleepMinutes: asleepMinutes, highMinutes: highMinutes)
        return WidgetSnapshot(
            night: night, status: status, asleepMinutes: asleepMinutes, lines: lines,
            headline: Headline.make(
                lines: lines, status: status, contributors: [sampleHRV(night: night, value: hrv, nights: earlierNights)], asleepMinutes: asleepMinutes),
            stressNow: sampleStress(level: stressLevel, at: now), stressDays: earlierNights >= 7 ? 12 : 3, earlierNights: earlierNights,
            syncedAt: now.addingTimeInterval(-syncedAgo)
        )
    }
}

extension VeselEntry {
    /// The states a widget preview steps through: normal, low, still learning, no data, old.
    static func previewStates(at now: Date = Date(timeIntervalSince1970: 1_793_005_200)) -> [VeselEntry] {
        [
            VeselEntry(date: now, snapshot: .sampleReady(at: now)),
            VeselEntry(date: now, snapshot: .sampleReady(at: now, indicator: 2, subLevel: 20, asleepMinutes: 300, highMinutes: 48, hrv: 38, stressLevel: 75)),
            VeselEntry(date: now, snapshot: .sampleReady(at: now, earlierNights: 3)),
            VeselEntry(date: now, snapshot: .empty),
            VeselEntry(date: now, snapshot: .sampleReady(at: now, syncedAgo: 14 * 3600)),
        ]
    }
}
#endif
