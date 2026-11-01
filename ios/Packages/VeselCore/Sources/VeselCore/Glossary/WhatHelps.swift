import Foundation

/// Something that was off, for "What tends to help".
public enum HelpTopic: Sendable, Equatable, CaseIterable {
    case lowRecovery, lowHRV, highRestingHeartRate, breathingOrSkinOff, shortSleep, longSleep, highStress
}

/// "What tends to help": fixed, reviewed tips per thing that was off. General advice for most people; screens pass
/// topics and never write their own tips.
public enum WhatHelps {
    public static let label = "General advice for most people, not medical advice."
    static let maximumTips = 5

    /// The tips for `topics`, no tip twice, at most 5: each topic's first tip in topic order, then each one's second,
    /// and so on, so every topic gets a say. A `{…}` part shows only with its number; the busiest-hours tip only with
    /// `busiestHours` (today's Calm page).
    public static func tips(for topics: [HelpTopic], usualBedtime: String?, busiestHours: String?) -> [String] {
        let bedtime = usualBedtime.map { ", about \($0)" } ?? ""
        let lists = topics.map { tips($0, bedtime: bedtime, busiestHours: busiestHours) }
        var result: [String] = []
        for index in 0..<(lists.map(\.count).max() ?? 0) {
            for list in lists where index < list.count && !result.contains(list[index]) {
                result.append(list[index])
            }
        }
        return Array(result.prefix(maximumTips))
    }

    /// The Recovery page's topics: recovery below its normal, HRV lower or resting heart rate higher than usual
    /// (beyond 1 SD), breathing or skin temperature much off (beyond 2 SD), and short sleep when sleep was the night's
    /// biggest departure.
    public static func recoveryTopics(lines: DayLines, contributors: [ContributorReading]) -> [HelpTopic] {
        func verdict(_ contributor: Contributor) -> RangeVerdict? { contributors.first { $0.contributor == contributor }?.verdict }
        var topics: [HelpTopic] = []
        if lines.recovery.state == .below { topics.append(.lowRecovery) }
        if [.lower, .wellBelow].contains(verdict(.hrv)) { topics.append(.lowHRV) }
        if [.higher, .wellAbove].contains(verdict(.restingHeartRate)) { topics.append(.highRestingHeartRate) }
        if [verdict(.breathing), verdict(.skinTemperature)].contains(where: { $0 == .wellBelow || $0 == .wellAbove }) {
            topics.append(.breathingOrSkinOff)
        }
        if lines.sleep.state == .below, RecoverySentence.driver(contributors)?.contributor == .sleep { topics.append(.shortSleep) }
        return topics
    }

    public static func sleepTopics(lines: DayLines) -> [HelpTopic] {
        switch lines.sleep.state {
        case .below: [.shortSleep]
        case .above: [.longSleep]
        default: []
        }
    }

    public static func calmTopics(lines: DayLines) -> [HelpTopic] {
        lines.calm.state == .above ? [.highStress] : []
    }

    private static func tips(_ topic: HelpTopic, bedtime: String, busiestHours: String?) -> [String] {
        switch topic {
        case .lowRecovery, .lowHRV:
            [
                "Keep the next day lighter: an easy walk instead of a hard workout.",
                "Go to bed around your usual time\(bedtime), and keep it steady for a few nights.",
                "Skip alcohol before bed; for most people it lowers HRV and recovery.",
                "Drink water through the day.",
                "Feeling run down? Rest. A low HRV can come before a cold.",
            ]
        case .highRestingHeartRate:
            [
                "Alcohol, a late heavy meal or a hot room can raise your resting heart rate the night after.",
                "Drink water through the day.",
                "If you feel ill, take it easy until it settles.",
            ]
        case .breathingOrSkinOff:
            [
                "Faster breathing or a warmer night can come before a cold. Rest and see how you feel.",
                "If it stays off for several nights and you feel unwell, talk to a doctor.",
            ]
        case .shortSleep:
            [
                "Aim for bed around your usual time\(bedtime).",
                "No coffee after 14:00.",
                "Dim screens for the last hour before bed.",
                "A cool, dark room helps you stay asleep.",
            ]
        case .longSleep:
            [
                "A long night can be catching up or your body fighting something off. Notice how you feel.",
                "Get daylight soon after you wake; it helps keep your rhythm.",
                "If long nights keep coming and you feel unwell, talk to a doctor.",
            ]
        case .highStress:
            [
                "Try slow breathing: in for 4, out for 6, for two minutes.",
                "A short walk outside, even ten minutes.",
            ] + (busiestHours.map { ["Plan a break before your busiest hours, about \($0)."] } ?? [])
        }
    }
}
