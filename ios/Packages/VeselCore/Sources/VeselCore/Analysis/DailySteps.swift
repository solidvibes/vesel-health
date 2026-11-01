import Foundation

/// A day's steps as the Loop's daily summary counts them, and your normal of them.
public enum DailySteps {
    public static let method = "activity.steps"
    public static let version = 1

    /// The day's total as a trend point, read from the daily summary and never stored as a metric. `readAt` is when the band was read for it.
    public static func metric(day: DayKey, steps: Int, readAt: Date) -> ComputedMetric {
        ComputedMetric(
            kind: MetricKind.steps, day: day, hour: nil, value: Double(steps), unit: "steps",
            explanation: Explanation(
                method: method, version: version,
                inputs: [.init(name: "Steps", value: Double(steps), unit: "steps")],
                text:
                    "The Loop's own count of your steps for the day, from its daily summary, as of the last time Vesel read your band. A day that isn't over is still counting. Your normal is the average of your previous \(PersonalRange.windowNights) days, plus and minus one standard deviation, from \(PersonalRange.minimumNights) days on."
            ),
            computedAt: readAt
        )
    }

    /// The same normal as every other measure (`PersonalRange`): the previous 28 days, not counting `day`. Nil under 7 days; never below 0.
    public static func normal(before day: DayKey, in steps: [DayKey: Double]) -> ClosedRange<Double>? {
        PersonalRange(previous: PersonalRange.previousValues(before: day, in: steps)).map { max($0.low, 0)...$0.high }
    }
}
