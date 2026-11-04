import Foundation

/// Your usual bedtime (`usualBedtime`, version 1): the median sleep start of the previous 28 nights, at least 7, as a
/// clock time in the phone's zone, rounded to 5 minutes. Counted from 18:00 so midnight doesn't split it. Worked out on
/// read, never stored.
public struct UsualBedtime: Sendable, Equatable {
    public static let method = "usualBedtime"
    public static let version = 1

    /// "23:10"
    public var text: String
    public var explanation: Explanation

    /// `starts` are the sleep starts of the nights before the one shown, at most 28. Nil with fewer than 7.
    public static func make(starts: [Date], zone: TimeZone) -> UsualBedtime? {
        guard starts.count >= PersonalRange.minimumNights, let median = ClockMedian(of: starts, zone: zone) else { return nil }
        return UsualBedtime(
            text: median.text,
            explanation: Explanation(
                method: method, version: version,
                inputs: [
                    .init(name: "nights", value: Double(starts.count), unit: "nights"),
                    .init(name: "minutesAfter18", value: Double(median.minutesAfter18), unit: "min"),
                ],
                text: "Your usual bedtime is the middle sleep start of your previous \(starts.count) nights, rounded to 5 minutes: \(median.text)."
            )
        )
    }
}
