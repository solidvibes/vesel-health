import Foundation

/// A number Vesel worked out, with how it was worked out. `hour` is nil for whole-day values.
public struct ComputedMetric: Sendable, Equatable {
    public var kind: String
    public var day: DayKey
    public var hour: Int?
    public var value: Double
    public var unit: String
    public var explanation: Explanation
    public var computedAt: Date

    public init(kind: String, day: DayKey, hour: Int?, value: Double, unit: String, explanation: Explanation, computedAt: Date) {
        self.kind = kind
        self.day = day
        self.hour = hour
        self.value = value
        self.unit = unit
        self.explanation = explanation
        self.computedAt = computedAt
    }
}
