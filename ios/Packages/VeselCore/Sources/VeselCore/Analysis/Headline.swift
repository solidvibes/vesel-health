import Foundation

/// Today's sentence on recovery, sleep and calm, and one line on why, from a fixed rule table (`headline`, version 3).
/// The first matching rule wins; the rules are listed in `docs/how-it-works/recovery.md`.
public struct Headline: Sendable, Equatable {
    public static let method = "headline"
    public static let version = 3

    public var sentence: String
    public var why: String
    public var explanation: Explanation

    /// `lines` holds the shown night's recovery and sleep and today's calm. Nil with no night stored and no calm judged
    /// today: Today shows its empty state. `units` writes the skin temperature in the why line.
    public static func make(
        lines: DayLines, status: RecoveryStatus?, contributors: [ContributorReading], asleepMinutes: Double?, units: Units = .metric
    ) -> Headline? {
        let recovery = lines.recovery.state
        let sleep = lines.sleep.state
        let calm = lines.calm.state
        let calmJudged = calm == .inside || calm == .above

        if status == nil && asleepMinutes == nil {
            guard calmJudged else { return nil }
            return headline(
                1.5, "No sleep recorded last night.", calm == .inside ? "A calm day so far." : calmLine(lines.calm),
                "There is no night of sleep stored, so the sentence says so. The second line is about today's stress.")
        }
        if recovery.isLearning || sleep.isLearning {
            return headline(
                2, "Getting to know you.", "",
                "Recovery or sleep is still learning your normal, which needs \(PersonalRange.minimumNights) earlier nights, so the sentence says Vesel is getting to know you."
            )
        }
        guard let status else {
            return headline(
                3, "Polar hasn't scored your recovery yet.", asleepMinutes.map { "\(DurationText.hoursMinutes(minutes: $0)) asleep." } ?? "",
                "There is a night of sleep but no Nightly Recharge yet, so the sentence says Polar hasn't scored your recovery. The second line gives your time asleep."
            )
        }
        let polar = "Polar's Nightly Recharge is \(status.indicator) of 6 (\(status.word))"
        if recovery == .below {
            let driver = RecoverySentence.driver(contributors)
            var parts = driver.map { [RecoverySentence.describe($0, units: units) + "."] } ?? []
            if driver?.contributor != .sleep, let also = sleepAlso(sleep) { parts.append(also) }
            if calm == .above { parts.append("Stress is also above your normal.") }
            if parts.isEmpty { parts.append(noneStoodOut) }
            let reason =
                "Recovery is below your normal: \(polar), so the sentence says recovery is "
                + "\(status.indicator == 3 ? "lower than usual" : "low"). The second line names the contributor furthest from your usual "
                + "(more than 1 standard deviation away), then any other line outside its normal. With none of them that far out, it says Polar weighs the readings together."
            return status.indicator == 3
                ? headline(4, "Recovery is lower than usual today.", parts.joined(separator: " "), reason, status)
                : headline(5, "Recovery is low today.", parts.joined(separator: " "), reason, status)
        }
        if sleep.isOutside, let asleep = lines.sleep.scale?.value, let low = lines.sleep.normal.low, let high = lines.sleep.normal.high {
            let usual = "your usual of \(DurationText.hoursMinutes(minutes: low)) to \(DurationText.hoursMinutes(minutes: high))"
            let calmPart = calm == .above ? " Stress is also above your normal." : ""
            if sleep == .below {
                return headline(
                    6, "You slept less than usual.", "\(DurationText.hoursMinutes(minutes: asleep)) is under \(usual).\(calmPart)",
                    "Sleep is below your normal, so the sentence says you slept less than usual. The second line gives the numbers.", status)
            }
            return headline(
                7, "You slept longer than usual.",
                "\(DurationText.hoursMinutes(minutes: asleep)) is over \(usual); it can mean catching up, or your body asking for rest.\(calmPart)",
                "Sleep is above your normal, so the sentence says you slept longer than usual. The second line gives the numbers.", status)
        }
        if calm == .above {
            return headline(
                8, "More stress than usual today.", calmLine(lines.calm),
                "Today's high-stress minutes are above your usual, so the sentence says there is more stress than usual. The second line gives the numbers.",
                status)
        }
        var good: [String] = []
        if recovery == .inside { good.append(encouraging(status.indicator)) }
        if sleep == .inside { good.append("your sleep was right in your normal") }
        if calm == .inside { good.append("a calm day so far") }
        let okNight = recovery == .inside && status.indicator == InRange.recoveryInside
        return headline(
            9, okNight ? "Things look good today." : "Everything looks great today.", joined(good),
            "Every line with data is inside your normal and \(polar), so the sentence says things look \(okNight ? "good" : "great"). The second line names each line that is inside.",
            status
        )
    }

    private static let noneStoodOut = "None of last night's readings stood out on its own; Polar weighs them together."

    private static func headline(_ rule: Double, _ sentence: String, _ why: String, _ text: String, _ status: RecoveryStatus? = nil) -> Headline {
        var inputs: [Explanation.Input] = [.init(name: "rule", value: rule, unit: "of 9")]
        if let status { inputs.append(.init(name: "recoveryIndicator", value: Double(status.indicator), unit: "of 6")) }
        return Headline(sentence: sentence, why: why, explanation: Explanation(method: method, version: version, inputs: inputs, text: text))
    }

    private static func sleepAlso(_ state: LineState) -> String? {
        switch state {
        case .below: "Sleep was also shorter than usual."
        case .above: "Sleep was also longer than usual."
        default: nil
        }
    }

    private static func calmLine(_ calm: LineVerdict) -> String {
        guard let minutes = calm.scale?.value, let allowance = calm.normal.high else { return "" }
        return "\(DurationText.hoursMinutes(minutes: minutes)) of high stress so far; your usual is up to \(DurationText.hoursMinutes(minutes: allowance))."
    }

    private static func encouraging(_ indicator: Int) -> String {
        switch indicator {
        case 6: "You're well recovered"
        case 5: "Recovery is good"
        default: "Recovery is OK"
        }
    }

    /// "A, B, and C." with the first letter in capitals.
    private static func joined(_ parts: [String]) -> String {
        guard let first = parts.first else { return "" }
        let text = parts.count == 1 ? first : parts.dropLast().joined(separator: ", ") + ", and " + parts.last!
        return text.prefix(1).uppercased() + text.dropFirst() + "."
    }
}
