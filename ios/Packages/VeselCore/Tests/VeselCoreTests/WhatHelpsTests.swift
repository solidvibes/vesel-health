import Foundation
import Testing
import VeselCore

struct WhatHelpsTests {
    @Test func lowRecoveryAndLowHRVShareTheirTipsOnce() {
        let tips = WhatHelps.tips(for: [.lowRecovery, .lowHRV], usualBedtime: "23:10", busiestHours: nil)
        #expect(
            tips == [
                "Keep the next day lighter: an easy walk instead of a hard workout.",
                "Go to bed around your usual time, about 23:10, and keep it steady for a few nights.",
                "Skip alcohol before bed; for most people it lowers HRV and recovery.",
                "Drink water through the day.",
                "Feeling run down? Rest. A low HRV can come before a cold.",
            ])
    }

    @Test func withoutABedtimeTheNumberIsLeftOut() {
        let tips = WhatHelps.tips(for: [.lowRecovery], usualBedtime: nil, busiestHours: nil)
        #expect(tips.contains("Go to bed around your usual time, and keep it steady for a few nights."))
        #expect(WhatHelps.tips(for: [.shortSleep], usualBedtime: nil, busiestHours: nil).first == "Aim for bed around your usual time.")
    }

    @Test func everyTopicGetsASayWithinFiveTips() {
        let tips = WhatHelps.tips(for: [.lowHRV, .highRestingHeartRate, .breathingOrSkinOff], usualBedtime: nil, busiestHours: nil)
        #expect(
            tips == [
                "Keep the next day lighter: an easy walk instead of a hard workout.",
                "Alcohol, a late heavy meal or a hot room can raise your resting heart rate the night after.",
                "Faster breathing or a warmer night can come before a cold. Rest and see how you feel.",
                "Go to bed around your usual time, and keep it steady for a few nights.",
                "Drink water through the day.",
            ])
    }

    @Test func theBusiestHoursTipOnlyWithItsHours() {
        #expect(
            WhatHelps.tips(for: [.highStress], usualBedtime: nil, busiestHours: "14:00–16:00").last
                == "Plan a break before your busiest hours, about 14:00–16:00.")
        #expect(WhatHelps.tips(for: [.highStress], usualBedtime: nil, busiestHours: nil).count == 2)
    }

    @Test func topicsFollowWhatWasOff() {
        // HRV 26 is 2 SDs below its usual 42; resting heart rate 56 is 1 SD above 54, so still usual.
        var earlier = history(.hrv, [30, 34, 38, 42, 46, 50, 54])
        for (key, value) in history(.restingHeartRate, [51, 52, 53, 54, 55, 56, 57]) { earlier[key, default: [:]].merge(value) { $1 } }
        let contributors = readings([.hrv: 26, .restingHeartRate: 56], history: earlier)
        let status = RecoveryStatus(NightlyRecharge(night: day("2026-10-26"), recoveryIndicator: 2, recoveryIndicatorSubLevel: 0))
        let lines = DayLines(
            recovery: InRange.recovery(status: status, earlierNights: 20), sleep: InRange.sleep(nil),
            calm: InRange.calm(minutes: 45, previous: Array(repeating: 20, count: 7))
        )
        #expect(WhatHelps.recoveryTopics(lines: lines, contributors: contributors) == [.lowRecovery, .lowHRV])
        #expect(WhatHelps.sleepTopics(lines: lines) == [])
        #expect(WhatHelps.calmTopics(lines: lines) == [.highStress])
    }
}
