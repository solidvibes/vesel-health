import Foundation

/// When one night's sleep began and ended.
public struct SleepNightTimes: Sendable, Equatable {
    public var night: DayKey
    public var start: Date
    public var end: Date

    public init(night: DayKey, start: Date, end: Date) {
        self.night = night
        self.start = start
        self.end = end
    }
}

/// The middle bedtime and the middle wake time of some nights (`sleepTimes`, version 1): each the median clock time counted from
/// 18:00, in the phone's zone, rounded to 5 minutes. Worked out on read, never stored.
public struct SleepTimes: Sendable, Equatable {
    public static let method = "sleepTimes"
    public static let version = 1

    /// "23:20"
    public var bedtime: String
    /// "07:08"
    public var wake: String
    public var explanation: Explanation

    /// "23:20 to 07:08"
    public var text: String { "\(bedtime) to \(wake)" }

    /// Nil with no nights.
    public static func make(nights: [SleepNightTimes], zone: TimeZone) -> SleepTimes? {
        guard let bed = ClockMedian(of: nights.map(\.start), zone: zone), let wake = ClockMedian(of: nights.map(\.end), zone: zone) else { return nil }
        return SleepTimes(
            bedtime: bed.text, wake: wake.text,
            explanation: Explanation(
                method: method, version: version,
                inputs: [
                    .init(name: "nights", value: Double(nights.count), unit: "nights"),
                    .init(name: "bedtimeMinutesAfter18", value: Double(bed.minutesAfter18), unit: "min"),
                    .init(name: "wakeMinutesAfter18", value: Double(wake.minutesAfter18), unit: "min"),
                ],
                text:
                    "Your middle bedtime and wake time are the middle sleep start and the middle sleep end of these \(nights.count) nights, "
                    + "counted from 18:00 and rounded to 5 minutes: \(bed.text) to \(wake.text)."
            )
        )
    }
}
