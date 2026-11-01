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
        guard starts.count >= PersonalRange.minimumNights else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let sorted = starts.map { start in
            ((calendar.component(.hour, from: start) + 6) % 24) * 60 + calendar.component(.minute, from: start)
        }.sorted()
        let middle = sorted.count / 2
        let median = sorted.count % 2 == 0 ? Double(sorted[middle - 1] + sorted[middle]) / 2 : Double(sorted[middle])
        let rounded = Int((median / 5).rounded()) * 5
        let clock = (rounded + 18 * 60) % (24 * 60)
        let text = "\(pad(clock / 60)):\(pad(clock % 60))"
        return UsualBedtime(
            text: text,
            explanation: Explanation(
                method: method, version: version,
                inputs: [
                    .init(name: "nights", value: Double(starts.count), unit: "nights"), .init(name: "minutesAfter18", value: Double(rounded), unit: "min"),
                ],
                text: "Your usual bedtime is the middle sleep start of your previous \(starts.count) nights, rounded to 5 minutes: \(text)."
            )
        )
    }

    private static func pad(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
}
