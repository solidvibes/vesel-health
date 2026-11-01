import Foundation

/// Where a day's line stands against your own normal. Too little and too much both count as outside.
public enum LineState: Sendable, Equatable {
    case none
    case learning(soFar: Int, of: Int)
    case inside
    case below
    case above

    public var isOutside: Bool { self == .below || self == .above }

    public var isLearning: Bool {
        if case .learning = self { return true }
        return false
    }
}

/// What a day was judged against. Nil while learning or with no data.
public struct LineNormal: Sendable, Equatable {
    public var low: Double?
    public var high: Double?

    public static let none = LineNormal()

    public init(low: Double? = nil, high: Double? = nil) {
        self.low = low
        self.high = high
    }
}

/// Where the normal and the dot sit along the track, each 0...1, and the plotted number.
public struct LineScale: Sendable, Equatable {
    public var normalFrom: Double
    public var normalTo: Double
    public var dot: Double
    public var value: Double

    public init(normalFrom: Double, normalTo: Double, dot: Double, value: Double) {
        self.normalFrom = normalFrom
        self.normalTo = normalTo
        self.dot = dot
        self.value = value
    }

    /// A track from `trackLow` to `trackHigh`; anything past either end sits at that end.
    init(trackLow: Double, trackHigh: Double, normalLow: Double, normalHigh: Double, value: Double) {
        func position(_ number: Double) -> Double { min(max((number - trackLow) / (trackHigh - trackLow), 0), 1) }
        self.init(normalFrom: position(normalLow), normalTo: position(normalHigh), dot: position(value), value: value)
    }
}

public struct LineVerdict: Sendable, Equatable {
    public var state: LineState
    public var explanation: Explanation
    public var normal: LineNormal
    /// Nil for `none` and `learning`.
    public var scale: LineScale?

    public init(state: LineState, explanation: Explanation, normal: LineNormal, scale: LineScale?) {
        self.state = state
        self.explanation = explanation
        self.normal = normal
        self.scale = scale
    }
}

/// The range-line rule (`inRange`, version 2). Worked out on read, never stored.
public enum InRange {
    public static let method = "inRange"
    public static let version = 2
    /// Polar's "OK".
    public static let recoveryInside = 4
    /// The shortest stretch the track shows either side of a night's normal, in minutes.
    static let minimumSleepSpread = 60.0

    /// Polar's Nightly Recharge already compares the night with your usual: OK or better is inside.
    public static func recovery(status: RecoveryStatus?, earlierNights: Int) -> LineVerdict {
        guard let status else {
            return verdict(.none, [], "Polar hasn't scored this night.")
        }
        let inputs: [Explanation.Input] = [
            .init(name: "indicator", value: Double(status.indicator), unit: "of 6"),
            .init(name: "subLevel", value: Double(status.subLevel), unit: "of 100"),
            .init(name: "nights", value: Double(earlierNights), unit: "nights"),
        ]
        guard earlierNights >= PersonalRange.minimumNights else {
            return learning(earlierNights, "nights", inputs)
        }
        let normal = LineNormal(low: Double(recoveryInside))
        let value = min(max(Double(status.indicator) + Double(status.subLevel) / 100, 1), 6)
        let scale = LineScale(trackLow: 1, trackHigh: 6, normalLow: Double(recoveryInside), normalHigh: 6, value: value)
        let polar = "Polar's Nightly Recharge is \(status.word) (\(status.indicator) of 6)"
        guard status.indicator < recoveryInside else {
            return verdict(.inside, inputs, "\(polar): OK or better is inside your normal.", normal, scale)
        }
        return verdict(.below, inputs, "\(polar), below your normal, which starts at OK.", normal, scale)
    }

    /// Your normal time asleep, in minutes: from 1 SD under to 2 SD over the mean. The one source for the Sleep line and the Recovery page's Sleep row.
    static func sleepNormal(_ range: PersonalRange) -> (low: Double, high: Double) {
        (range.mean - range.sd, range.mean + 2 * range.sd)
    }

    /// Time asleep against your normal: from 1 SD under to 2 SD over the mean of the previous 28 nights.
    public static func sleep(_ reading: ContributorReading?) -> LineVerdict {
        guard let reading else {
            return verdict(.none, [], "No sleep recorded this night.")
        }
        var inputs: [Explanation.Input] = [
            .init(name: "asleep", value: reading.value, unit: "min"),
            .init(name: "nights", value: Double(reading.nights), unit: "nights"),
        ]
        guard let range = reading.range else {
            return learning(reading.nights, "nights", inputs)
        }
        let (low, high) = sleepNormal(range)
        inputs += [.init(name: "usualLow", value: low, unit: "min"), .init(name: "usualHigh", value: high, unit: "min")]
        let normal = LineNormal(low: low, high: high)
        let spread = max(high - low, minimumSleepSpread)
        let scale = LineScale(trackLow: max(low - spread, 0), trackHigh: high + spread, normalLow: low, normalHigh: high, value: reading.value)
        let asleep = DurationText.hoursMinutes(minutes: reading.value)
        let usual =
            "your normal is \(DurationText.hoursMinutes(minutes: low)) to \(DurationText.hoursMinutes(minutes: high)) "
            + "(from 1 SD under to 2 SD over the mean of your previous \(range.nights) nights)"
        let state: LineState = reading.value < low ? .below : reading.value > high ? .above : .inside
        return verdict(state, inputs, "\(asleep) asleep; \(usual), so this night is \(placed(state)) it.", normal, scale)
    }

    /// High-stress minutes against your usual allowance: the mean + 1 SD of `previous` (the counted days among the
    /// 28 before), never under `StressThresholds.calmAllowanceMinutes`. `minutes` is nil for a day that doesn't count.
    public static func calm(minutes: Double?, previous: [Double]) -> LineVerdict {
        guard let minutes else {
            return verdict(.none, [], "Not enough clean readings this day.")
        }
        var inputs: [Explanation.Input] = [
            .init(name: "highMinutes", value: minutes, unit: "min"),
            .init(name: "days", value: Double(previous.count), unit: "days"),
        ]
        guard let range = PersonalRange(previous: previous) else {
            return learning(previous.count, "days", inputs)
        }
        let allowance = max(range.high, StressThresholds.calmAllowanceMinutes)
        inputs.append(.init(name: "allowance", value: allowance, unit: "min"))
        let normal = LineNormal(high: allowance)
        let scale = LineScale(trackLow: 0, trackHigh: 2 * allowance, normalLow: 0, normalHigh: allowance, value: minutes)
        let high = DurationText.hoursMinutes(minutes: minutes)
        let limit = DurationText.hoursMinutes(minutes: allowance)
        let floor = DurationText.hoursMinutes(minutes: StressThresholds.calmAllowanceMinutes)
        let usual = "\(high) of high stress; your usual is up to \(limit) (mean + 1 SD of your previous \(range.nights) days, at least \(floor))"
        let state: LineState = minutes > allowance ? .above : .inside
        return verdict(state, inputs, "\(usual), so this day is \(placed(state)) it.", normal, scale)
    }

    /// A worn day before the stress baseline is ready: no high-stress minutes exist yet, so the calm line is learning.
    /// `baselineDays` is how many of the 14 days before have at least 10 clean readings.
    public static func calmBeforeBaseline(baselineDays: Int) -> LineVerdict {
        verdict(
            .learning(soFar: baselineDays, of: StressThresholds.minimumDays),
            [.init(name: "baselineDays", value: Double(baselineDays), unit: "days")],
            "Learning your normal: your calm baseline needs \(StressThresholds.minimumDays) earlier days with at least \(StressThresholds.minimumWindowsPerDay) clean readings each; Vesel has \(baselineDays). High-stress minutes, and then your usual for them, follow once it is ready."
        )
    }

    private static func placed(_ state: LineState) -> String {
        switch state {
        case .below: "below"
        case .above: "above"
        default: "inside"
        }
    }

    private static func learning(_ soFar: Int, _ unit: String, _ inputs: [Explanation.Input]) -> LineVerdict {
        verdict(
            .learning(soFar: soFar, of: PersonalRange.minimumNights), inputs,
            "Learning your normal: \(soFar) of \(PersonalRange.minimumNights) earlier \(unit) so far."
        )
    }

    private static func verdict(
        _ state: LineState, _ inputs: [Explanation.Input], _ text: String, _ normal: LineNormal = .none, _ scale: LineScale? = nil
    ) -> LineVerdict {
        LineVerdict(state: state, explanation: Explanation(method: method, version: version, inputs: inputs, text: text), normal: normal, scale: scale)
    }
}
