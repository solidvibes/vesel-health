import Foundation

/// The middle of some clock times, counted from 18:00 so midnight doesn't split them, rounded to 5 minutes.
public struct ClockMedian: Sendable, Equatable {
    /// Minutes after 18:00, rounded to 5.
    public var minutesAfter18: Int

    /// Nil with no moments.
    public init?(of moments: [Date], zone: TimeZone) {
        guard !moments.isEmpty else { return nil }
        let sorted = moments.map { Self.minutesAfter18(of: $0, zone: zone) }.sorted()
        let middle = sorted.count / 2
        let median = sorted.count % 2 == 0 ? Double(sorted[middle - 1] + sorted[middle]) / 2 : Double(sorted[middle])
        minutesAfter18 = Int((median / 5).rounded()) * 5
    }

    /// Minutes after 18:00 of the clock time of `moment` in `zone`, not rounded.
    public static func minutesAfter18(of moment: Date, zone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return ((calendar.component(.hour, from: moment) + 6) % 24) * 60 + calendar.component(.minute, from: moment)
    }

    /// "23:10"
    public var text: String {
        let clock = (minutesAfter18 + 18 * 60) % (24 * 60)
        return "\(Self.pad(clock / 60)):\(Self.pad(clock % 60))"
    }

    private static func pad(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
}
