import Foundation
import Testing
@testable import VeselCore

struct StressGlanceTests {
    private let moment = Date(timeIntervalSince1970: 1_800_000_000)

    private func now(level: Double, startedAgo seconds: TimeInterval) -> StressNow {
        StressNow(
            ComputedMetric(
                kind: MetricKind.stressNow, day: DayKey(moment, in: .gmt), hour: nil, value: level, unit: "level",
                explanation: Explanation(
                    method: "stress", version: 2, inputs: [.init(name: "windowStart", value: moment.timeIntervalSince1970 - seconds, unit: "s")], text: ""),
                computedAt: moment
            ))!
    }

    @Test func learningBeforeSevenDays() {
        let glance = StressGlance(days: 6, now: now(level: 80, startedAgo: 60), at: moment)
        #expect(glance == StressGlance(ringText: "Learning", rowText: "Learning your normal"))
    }

    @Test func aRecentReadingShowsItsLevel() {
        let glance = StressGlance(days: 7, now: now(level: 70, startedAgo: 29 * 60), at: moment)
        #expect(glance == StressGlance(ringText: "High", rowText: "High · 70"))
    }

    @Test func aReadingOlderThanThirtyMinutesIsNotNow() {
        let glance = StressGlance(days: 7, now: now(level: 20, startedAgo: 30 * 60), at: moment)
        #expect(glance == StressGlance(ringText: "—", rowText: "No recent reading"))
    }

    @Test func recoveryIsLowFromCompromisedDown() {
        #expect((1...6).map(RecoveryStatus.isLow) == [true, true, true, false, false, false])
    }
}
