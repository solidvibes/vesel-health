import Foundation

/// Polar's Nightly Recharge verdict, shown as Polar gives it: 1 to 6 with a sub-level of 0 to 100.
public struct RecoveryStatus: Sendable, Equatable {
    public static let method = "recovery.status"
    public static let version = 2

    public var night: DayKey
    public var indicator: Int
    public var subLevel: Int

    /// The stored value: (indicator − 1 + sub-level ÷ 100) ÷ 6. The line follows `InRange.recovery`, not this.
    public var fill: Double {
        (Double(indicator - 1) + Double(subLevel) / 100) / 6
    }

    /// Polar's word for the indicator.
    public var word: String { Self.word(indicator: indicator) }

    public static func word(indicator: Int) -> String { words[indicator - 1] }

    /// Poor, very poor or compromised: the Recovery line turns to the warm colour.
    public static func isLow(indicator: Int) -> Bool { indicator <= 3 }

    private static let words = ["very poor", "poor", "compromised", "OK", "good", "very good"]

    public init?(_ recharge: NightlyRecharge) {
        guard let indicator = recharge.recoveryIndicator, (1...6).contains(indicator) else { return nil }
        night = recharge.night
        self.indicator = indicator
        subLevel = min(max(recharge.recoveryIndicatorSubLevel ?? 0, 0), 100)
    }

    public init?(_ metric: ComputedMetric) {
        guard metric.kind == MetricKind.recoveryStatus,
            let indicator = metric.explanation.inputs.first(where: { $0.name == "indicator" })?.value,
            let subLevel = metric.explanation.inputs.first(where: { $0.name == "subLevel" })?.value,
            (1...6).contains(Int(indicator))
        else { return nil }
        night = metric.day
        self.indicator = Int(indicator)
        self.subLevel = Int(subLevel)
    }

    public func metric(computedAt: Date) -> ComputedMetric {
        ComputedMetric(
            kind: MetricKind.recoveryStatus, day: night, hour: nil, value: fill, unit: "fraction",
            explanation: Explanation(
                method: Self.method, version: Self.version,
                inputs: [.init(name: "indicator", value: Double(indicator), unit: "of 6"), .init(name: "subLevel", value: Double(subLevel), unit: "of 100")],
                text: "Polar's Nightly Recharge says \(word) (\(indicator) of 6)."
            ),
            computedAt: computedAt
        )
    }
}
