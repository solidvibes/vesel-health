import Foundation

/// One reading worked out on read, with its level against the baseline stored for its day.
public struct StressReading: Sendable, Equatable {
    public var start: Date
    /// Milliseconds.
    public var rmssd: Double
    /// 0 to 100.
    public var level: Double
    public var baseline: StressBaseline

    public init(start: Date, rmssd: Double, level: Double, baseline: StressBaseline) {
        self.start = start
        self.rmssd = rmssd
        self.level = level
        self.baseline = baseline
    }

    public var band: StressLevel { StressLevel(level: level) }
}
