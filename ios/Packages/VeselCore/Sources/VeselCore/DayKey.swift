import Foundation

/// A local calendar day, written `yyyy-MM-dd`. A night is keyed by the local date it ends on.
public struct DayKey: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, in timeZone: TimeZone) {
        let calendar = Self.calendar(timeZone)
        self.init(
            year: calendar.component(.year, from: date), month: calendar.component(.month, from: date), day: calendar.component(.day, from: date)
        )
    }

    public init?(_ string: String) {
        let parts = string.split(separator: "-")
        guard parts.count == 3,
            let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
            (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    public static func night(endingAt end: Date, in timeZone: TimeZone) -> DayKey {
        DayKey(end, in: timeZone)
    }

    public var description: String {
        "\(Self.pad(year, 4))-\(Self.pad(month, 2))-\(Self.pad(day, 2))"
    }

    public func start(in timeZone: TimeZone) -> Date {
        Self.calendar(timeZone).date(from: DateComponents(year: year, month: month, day: day))!
    }

    public func adding(days: Int) -> DayKey {
        let utc = TimeZone(identifier: "UTC")!
        let date = Self.calendar(utc).date(byAdding: .day, value: days, to: start(in: utc))!
        return DayKey(date, in: utc)
    }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let key = DayKey(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a yyyy-MM-dd day: \(string)")
        }
        self = key
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    private static func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}
