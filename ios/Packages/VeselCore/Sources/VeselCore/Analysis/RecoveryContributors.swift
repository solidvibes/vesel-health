import Foundation

/// The five things that feed recovery, each judged against your own usual.
public enum Contributor: String, CaseIterable, Sendable {
    case hrv, restingHeartRate, sleep, breathing, skinTemperature

    public var kind: String { "recovery.\(rawValue)" }

    public var title: String {
        switch self {
        case .hrv: "HRV"
        case .restingHeartRate: "Resting heart rate"
        case .sleep: "Sleep"
        case .breathing: "Breathing"
        case .skinTemperature: "Skin temperature"
        }
    }

    public var unit: String {
        switch self {
        case .hrv: "ms"
        case .restingHeartRate: "bpm"
        case .sleep: "min"
        case .breathing: "breaths/min"
        case .skinTemperature: "°C"
        }
    }

    var decimals: Int {
        switch self {
        case .hrv, .sleep: 0
        case .restingHeartRate, .breathing, .skinTemperature: 1
        }
    }

    public init?(kind: String) {
        guard let found = Self.allCases.first(where: { $0.kind == kind }) else { return nil }
        self = found
    }

    public var better: NormalMark.Better {
        switch self {
        case .hrv, .sleep: .higher
        case .restingHeartRate: .lower
        case .breathing, .skinTemperature: .neither
        }
    }

    /// A value as the screens write it: "6 h 05 m", "54.5 bpm"; skin temperature in `units`. Explanation texts stay metric.
    public func text(_ value: Double, units: Units = .metric) -> String {
        if self == .sleep { return DurationText.hoursMinutes(minutes: value) }
        if self == .skinTemperature { return units.temperatureText(celsius: value) }
        return "\(NumberText.decimal(value, decimals)) \(unit)"
    }
}

/// One night's numbers for each contributor, and what Polar measured to get them.
public struct ContributorValues: Sendable, Equatable {
    public var values: [Contributor: Double]
    var sources: [Contributor: Explanation.Input]

    public init(values: [Contributor: Double] = [:]) {
        self.values = values
        sources = [:]
    }
}

public enum RecoveryContributors {
    public static let method = "recovery"
    public static let version = 2

    /// HRV is Polar's nightly RMSSD; resting heart rate and breathing come from Polar's nightly mean intervals;
    /// sleep is time asleep; skin temperature is the mean of the readings between sleep start and end.
    public static func values(recharge: NightlyRecharge?, summary: SleepSummary?, skinTemperatures: [SkinTemperatureSample]) -> ContributorValues {
        var result = ContributorValues()
        if let rmssd = recharge?.meanNightlyRecoveryRMSSD {
            result.values[.hrv] = Double(rmssd)
        }
        if let rri = recharge?.meanNightlyRecoveryRRI, rri > 0 {
            result.values[.restingHeartRate] = 60_000 / Double(rri)
            result.sources[.restingHeartRate] = .init(name: "meanBeatInterval", value: Double(rri), unit: "ms")
        }
        if let interval = recharge?.meanNightlyRecoveryRespirationInterval, interval > 0 {
            result.values[.breathing] = 60_000 / Double(interval)
            result.sources[.breathing] = .init(name: "meanBreathInterval", value: Double(interval), unit: "ms")
        }
        if let summary {
            result.values[.sleep] = Double(summary.asleepSeconds) / 60
            let temperatures = skinTemperatures.filter { $0.time >= summary.start && $0.time <= summary.end }.map(\.celsius)
            if !temperatures.isEmpty {
                result.values[.skinTemperature] = temperatures.reduce(0, +) / Double(temperatures.count)
                result.sources[.skinTemperature] = .init(name: "readings", value: Double(temperatures.count), unit: "readings")
            }
        }
        return result
    }

    /// One metric per contributor the night has, each against the 28 nights before it in `history`.
    public static func metrics(night: DayKey, values: ContributorValues, history: [DayKey: [Contributor: Double]], computedAt: Date) -> [ComputedMetric] {
        Contributor.allCases.compactMap { contributor in
            guard let value = values.values[contributor] else { return nil }
            let previous = PersonalRange.previousValues(before: night, in: history.compactMapValues { $0[contributor] })
            let range = PersonalRange(previous: previous)

            var inputs: [Explanation.Input] = []
            if let source = values.sources[contributor] { inputs.append(source) }
            inputs.append(.init(name: "value", value: value, unit: contributor.unit))
            inputs.append(.init(name: "nights", value: Double(previous.count), unit: "nights"))
            if let range {
                inputs.append(.init(name: "usualMean", value: range.mean, unit: contributor.unit))
                inputs.append(.init(name: "usualSD", value: range.sd, unit: contributor.unit))
            }
            let shown =
                range.map { contributor == .skinTemperature ? " It shows as the difference from your usual mean of \(contributor.text($0.mean))." : "" } ?? ""
            let usual =
                range.map { range -> String in
                    if contributor == .sleep {
                        let normal = InRange.sleepNormal(range)
                        return
                            "Your normal is from 1 standard deviation under to 2 over the mean of your previous \(range.nights) nights: \(contributor.text(normal.low))–\(contributor.text(normal.high))."
                    }
                    return
                        "Your usual is the mean ± 1 standard deviation of your previous \(range.nights) nights: \(contributor.text(range.low))–\(contributor.text(range.high)).\(shown)"
                } ?? "Your usual needs \(PersonalRange.minimumNights) earlier nights to compare against; Vesel has \(previous.count)."
            return ComputedMetric(
                kind: contributor.kind, day: night, hour: nil, value: value, unit: contributor.unit,
                explanation: Explanation(
                    method: method, version: version, inputs: inputs,
                    text: "\(source(contributor, value, values.sources[contributor])) \(usual)"
                ),
                computedAt: computedAt
            )
        }
    }

    private static func source(_ contributor: Contributor, _ value: Double, _ source: Explanation.Input?) -> String {
        let interval = source.map { NumberText.decimal($0.value, 0) } ?? "?"
        switch contributor {
        case .hrv: return "HRV is Polar's average nightly RMSSD: \(contributor.text(value))."
        case .restingHeartRate:
            return "Resting heart rate is 60 000 ÷ the mean beat interval Polar measured overnight (\(interval) ms): \(contributor.text(value))."
        case .breathing: return "Breathing is 60 000 ÷ the mean breath interval Polar measured overnight (\(interval) ms): \(contributor.text(value))."
        case .sleep: return "Sleep is your time asleep from Polar's sleep result: \(contributor.text(value))."
        case .skinTemperature: return "Skin temperature is the mean of the band's readings while you slept: \(contributor.text(value))."
        }
    }
}

/// A stored contributor metric, read back with its range.
public struct ContributorReading: Sendable, Equatable {
    public var contributor: Contributor
    public var night: DayKey
    public var value: Double
    public var nights: Int
    public var range: PersonalRange?
    public var explanation: Explanation

    public init?(_ metric: ComputedMetric) {
        guard let contributor = Contributor(kind: metric.kind) else { return nil }
        self.contributor = contributor
        night = metric.day
        value = metric.value
        explanation = metric.explanation
        func input(_ name: String) -> Double? { metric.explanation.inputs.first { $0.name == name }?.value }
        nights = Int(input("nights") ?? 0)
        range = input("usualMean").flatMap { mean in input("usualSD").map { PersonalRange(mean: mean, sd: $0, nights: nights) } }
    }

    /// Sleep is judged against its own normal (`InRange.sleep`): under 1 SD below the mean is lower, under 2 SD well below,
    /// over 2 SD above is well above.
    public var verdict: RangeVerdict {
        guard let range else { return .learning(nights: nights) }
        guard contributor == .sleep else { return range.verdict(of: value) }
        let normal = InRange.sleepNormal(range)
        if value > normal.high { return .wellAbove }
        if value >= normal.low { return .usual }
        return range.sd == 0 || value >= range.mean - 2 * range.sd ? .lower : .wellBelow
    }

    /// Nil while learning. Sleep above its normal is off, never better.
    public var mark: NormalMark? {
        if contributor == .sleep, verdict == .wellAbove { return .off(.above) }
        return NormalMark(verdict: verdict, better: contributor.better)
    }

    /// The verdict in words: sleep reads "shorter"/"longer" than usual, the others "lower"/"higher".
    public var verdictWord: String? {
        guard contributor == .sleep else { return verdict.word }
        switch verdict {
        case .wellBelow: return "much shorter than usual"
        case .lower, .higher: return "shorter than usual"
        case .wellAbove: return "longer than usual"
        case .usual: return "usual"
        case .learning: return nil
        }
    }

    /// Tonight's value minus your usual; nil while Vesel is still learning it.
    public var difference: Double? {
        range.map { value - $0.mean }
    }

    /// How far from usual, in standard deviations; nil while learning. Sleep inside its normal counts as 0 and past its upper end
    /// (2 SD) as 1 SD less, so beyond 1 here always means outside the normal.
    public var spreads: Double? {
        guard let range, let difference else { return nil }
        if range.sd == 0 { return difference == 0 ? 0 : (difference > 0 ? .infinity : -.infinity) }
        let spreads = difference / range.sd
        guard contributor == .sleep else { return spreads }
        if spreads < -1 { return spreads }
        if spreads > 2 { return spreads - 1 }
        return 0
    }

    /// "34 ms–52 ms"
    public func usualText(units: Units = .metric) -> String? {
        range.map { "\(contributor.text($0.low, units: units))–\(contributor.text($0.high, units: units))" }
    }

    public func valueText(units: Units = .metric) -> String { contributor.text(value, units: units) }

    /// "+0.3 °C", for skin temperature shown against your usual.
    public func differenceText(units: Units = .metric) -> String? {
        difference.map {
            if contributor == .skinTemperature { return units.temperatureDifferenceText(celsius: $0) }
            return "\($0 >= 0 ? "+" : "−")\(NumberText.decimal(abs($0), 1)) \(contributor.unit)"
        }
    }
}
