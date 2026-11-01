import Foundation

/// How calm you usually are: the 80th percentile of the last 14 days' daytime readings (ln RMSSD), and the
/// 5th percentile as the floor. Needs 7 days with at least 10 readings each (`stress`, version 2).
public struct StressBaseline: Sendable, Equatable {
    public var baseline: Double
    public var floor: Double
    /// Days that had enough readings and went into it.
    public var days: Int
    public var windows: Int

    public enum Outcome: Sendable, Equatable {
        /// `days` is how many earlier days have enough readings so far.
        case learning(days: Int)
        case ready(StressBaseline)
    }

    public init(baseline: Double, floor: Double, days: Int, windows: Int) {
        self.baseline = baseline
        self.floor = floor
        self.days = days
        self.windows = windows
    }

    /// The baseline and floor a day was worked out against, from the inputs of its `stress.readings`; nil while that day was still learning.
    public init?(stored inputs: [Explanation.Input]) {
        func input(_ name: String) -> Double? { inputs.first { $0.name == name }?.value }
        guard let baseline = input("baseline"), let floor = input("floor") else { return nil }
        self.init(baseline: baseline, floor: floor, days: Int(input("baselineDays") ?? 0), windows: Int(input("baselineReadings") ?? 0))
    }

    /// The 14 days before `day`, never the day itself. `valuesByDay` holds each day's reading values (ln RMSSD).
    public static func make(before day: DayKey, valuesByDay: [DayKey: [Double]]) -> Outcome {
        let enough = previousDays(before: day).compactMap { valuesByDay[$0] }.filter { $0.count >= StressThresholds.minimumWindowsPerDay }
        guard enough.count >= StressThresholds.minimumDays else { return .learning(days: enough.count) }
        let values = enough.flatMap { $0 }.sorted()
        return .ready(
            StressBaseline(
                baseline: percentile(values, StressThresholds.baselinePercentile),
                floor: percentile(values, StressThresholds.floorPercentile),
                days: enough.count,
                windows: values.count
            ))
    }

    /// How many of the 14 days before `day` have at least 10 readings, given each day's reading count.
    public static func qualifyingDays(before day: DayKey, counts: [DayKey: Int]) -> Int {
        previousDays(before: day).filter { (counts[$0] ?? 0) >= StressThresholds.minimumWindowsPerDay }.count
    }

    /// 0 (as calm as your baseline or calmer) to 100 (at or below your floor).
    public func level(of value: Double) -> Double {
        guard baseline > floor else { return value < baseline ? 100 : 0 }
        return min(max((baseline - value) / (baseline - floor) * 100, 0), 100)
    }

    /// Linear between the two nearest values: position p × (n − 1) in the sorted list.
    static func percentile(_ sorted: [Double], _ share: Double) -> Double {
        let position = share * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Double(lower))
    }

    private static func previousDays(before day: DayKey) -> [DayKey] {
        (1...StressThresholds.baselineDays).map { day.adding(days: -$0) }
    }
}
