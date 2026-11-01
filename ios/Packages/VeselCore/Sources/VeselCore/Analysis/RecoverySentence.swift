import Foundation

/// The Recovery page's sentence on Polar's Nightly Recharge, and one line on why, from a fixed rule table
/// (`recoverySentence`, version 1: the wording of `headline` version 2). The rules are listed in `docs/how-it-works/recovery.md`.
public struct RecoverySentence: Sendable, Equatable {
    public static let method = "recoverySentence"
    public static let version = 1

    public var sentence: String
    public var why: String
    public var explanation: Explanation

    /// Nil when there is neither a recovery status nor a night of sleep. `units` writes the skin temperature in the why line.
    public static func make(status: RecoveryStatus?, contributors: [ContributorReading], asleepMinutes: Double?, units: Units = .metric) -> RecoverySentence? {
        let rule: (number: Int, sentence: String)
        if let status {
            switch status.indicator {
            case 6: rule = (1, "You're well recovered.")
            case 5: rule = (2, "Recovery is good.")
            case 4: rule = (3, "Recovery is OK.")
            case 3: rule = (4, "Recovery is lower than usual.")
            default: rule = (5, "Recovery is low.")
            }
        } else if asleepMinutes != nil {
            rule = (6, "Polar hasn't scored your recovery yet.")
        } else {
            return nil
        }

        var parts: [String] = []
        if let driver = driver(contributors) {
            parts.append(describe(driver, units: units))
        } else if let first = contributors.first {
            if case .learning(let nights) = first.verdict {
                parts.append(LearningText.nights(nights))
            } else {
                parts.append("Everything is within your usual range")
            }
        }
        if let asleepMinutes { parts.append("\(DurationText.hoursMinutes(minutes: asleepMinutes)) asleep") }

        var inputs: [Explanation.Input] = [.init(name: "rule", value: Double(rule.number), unit: "of 6")]
        if let status { inputs.append(.init(name: "recoveryIndicator", value: Double(status.indicator), unit: "of 6")) }
        return RecoverySentence(
            sentence: rule.sentence,
            why: parts.isEmpty ? "" : parts.joined(separator: "; ") + ".",
            explanation: Explanation(
                method: method, version: version, inputs: inputs,
                text: text(sentence: rule.sentence, status: status)
            )
        )
    }

    private static let ending = "The second line names the contributor furthest from your usual (more than 1 standard deviation away), then your time asleep."

    private static func text(sentence: String, status: RecoveryStatus?) -> String {
        guard let status else {
            return "There is a night of sleep but no Nightly Recharge yet, so the sentence says Polar hasn't scored your recovery. \(ending)"
        }
        return "The sentence follows Polar's Nightly Recharge: \(status.indicator) of 6 (\(status.word)) reads \"\(sentence)\" \(ending)"
    }

    /// The contributor furthest from your usual, when it is more than 1 standard deviation away.
    public static func driver(_ contributors: [ContributorReading]) -> ContributorReading? {
        contributors.compactMap { reading in reading.spreads.map { (reading, $0) } }
            .filter { abs($0.1) > 1 }
            .max { abs($0.1) < abs($1.1) }?.0
    }

    static func describe(_ reading: ContributorReading, units: Units) -> String {
        let direction = (reading.difference ?? 0) > 0 ? "above" : "below"
        let amount = abs(reading.difference ?? 0)
        switch reading.contributor {
        case .hrv:
            let percent = reading.range.map { $0.mean != 0 ? amount / $0.mean * 100 : 0 } ?? 0
            return "HRV \(NumberText.decimal(percent, 0)) % \(direction) your usual"
        case .restingHeartRate:
            return "Resting heart rate \(NumberText.decimal(amount, 0)) bpm \(direction) your usual"
        case .breathing:
            return "Breathing \(NumberText.decimal(amount, 1)) breaths/min \(direction) your usual"
        case .sleep:
            return "Sleep \(DurationText.hoursMinutes(minutes: amount)) \(direction == "above" ? "longer" : "shorter") than usual"
        case .skinTemperature:
            return "Skin temperature \(NumberText.decimal(units.temperatureDifference(celsius: amount), 1)) \(units.temperatureUnit) \(direction) your usual"
        }
    }
}
