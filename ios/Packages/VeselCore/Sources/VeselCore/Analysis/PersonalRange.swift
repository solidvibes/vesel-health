/// Where one value sits against your own usual.
public enum RangeVerdict: Sendable, Equatable {
    /// Fewer than 7 nights to compare against; `nights` is how many there are.
    case learning(nights: Int)
    case wellBelow, lower, usual, higher, wellAbove

    public var word: String? {
        switch self {
        case .learning: nil
        case .wellBelow: "much lower than usual"
        case .lower: "lower than usual"
        case .usual: "usual"
        case .higher: "higher than usual"
        case .wellAbove: "much higher than usual"
        }
    }
}

/// Your usual for one measure: the mean ± 1 standard deviation of the previous 28 nights (`range28`, version 1).
/// The night being judged is not part of its own range. Needs at least 7 values.
public struct PersonalRange: Sendable, Equatable {
    public static let method = "range28"
    public static let version = 1
    public static let windowNights = 28
    public static let minimumNights = 7

    public var mean: Double
    /// The spread of the nights in the range (population standard deviation).
    public var sd: Double
    public var nights: Int

    public var low: Double { mean - sd }
    public var high: Double { mean + sd }

    /// Sleep efficiency's normal, where only a clearly low night counts: 2 SD under to 1 SD over the mean, never over 100.
    public var lowNightsNormal: ClosedRange<Double> { (mean - 2 * sd)...min(mean + sd, 100) }

    public init(mean: Double, sd: Double, nights: Int) {
        self.mean = mean
        self.sd = sd
        self.nights = nights
    }

    /// Nil when there are fewer than 7 values.
    public init?(previous values: [Double]) {
        guard values.count >= Self.minimumNights else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
        self.init(mean: mean, sd: variance.squareRoot(), nights: values.count)
    }

    /// How a range worked out on read (not stored with a night) was made: `unit` is written after each number.
    public func explanation(unit: String, decimals: Int = 0) -> Explanation {
        Explanation(
            method: Self.method, version: Self.version,
            inputs: [
                .init(name: "nights", value: Double(nights), unit: "nights"),
                .init(name: "usualMean", value: mean, unit: unit),
                .init(name: "usualSD", value: sd, unit: unit),
            ],
            text:
                "Your usual is the mean ± 1 standard deviation of your previous \(nights) nights: "
                + "\(NumberText.decimal(low, decimals))–\(NumberText.decimal(high, decimals)) \(unit)."
        )
    }

    /// How the efficiency normal worked out on read was made (`range28Low`, version 1).
    public func lowNightsExplanation() -> Explanation {
        let normal = lowNightsNormal
        return Explanation(
            method: "range28Low", version: 1,
            inputs: [
                .init(name: "nights", value: Double(nights), unit: "nights"),
                .init(name: "usualMean", value: mean, unit: "%"),
                .init(name: "usualSD", value: sd, unit: "%"),
            ],
            text:
                "Your normal is from 2 standard deviations under to 1 over the mean of your previous \(nights) nights, so only a clearly low night is marked: "
                + "\(NumberText.decimal(normal.lowerBound, 0))–\(NumberText.decimal(normal.upperBound, 0)) %."
        )
    }

    /// The values of the 28 nights before `night` that have one.
    public static func previousValues(before night: DayKey, in valuesByNight: [DayKey: Double]) -> [Double] {
        (1...windowNights).compactMap { valuesByNight[night.adding(days: -$0)] }
    }

    /// The newest metric's night against the 28 nights before it in `metrics`. Nil under 7 earlier nights.
    public static func latest(of metrics: [ComputedMetric]) -> PersonalRange? {
        guard let newest = metrics.max(by: { $0.day < $1.day }) else { return nil }
        let byNight = Dictionary(metrics.map { ($0.day, $0.value) }, uniquingKeysWith: { _, last in last })
        return PersonalRange(previous: previousValues(before: newest.day, in: byNight))
    }

    /// While there is no usual yet: the median of the newest night and the 28 before it, and how many earlier nights that is.
    /// Nil under 2 values.
    public static func settling(of metrics: [ComputedMetric]) -> (median: Double, earlierNights: Int)? {
        guard let newest = metrics.max(by: { $0.day < $1.day }) else { return nil }
        let byNight = Dictionary(metrics.map { ($0.day, $0.value) }, uniquingKeysWith: { _, last in last })
        let earlier = previousValues(before: newest.day, in: byNight)
        guard !earlier.isEmpty else { return nil }
        let sorted = (earlier + [newest.value]).sorted()
        let middle = sorted.count / 2
        let median = sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
        return (median, earlier.count)
    }

    /// Within 1 SD of the mean is usual; beyond 2 SD is "well".
    public func verdict(of value: Double) -> RangeVerdict {
        let distance = value - mean
        if sd == 0 {
            return distance == 0 ? .usual : (distance > 0 ? .higher : .lower)
        }
        let spreads = distance / sd
        if spreads < -2 { return .wellBelow }
        if spreads < -1 { return .lower }
        if spreads <= 1 { return .usual }
        if spreads <= 2 { return .higher }
        return .wellAbove
    }
}
