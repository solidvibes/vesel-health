import Foundation

/// "I'm up" was tapped and the Loop hasn't ended the night for it yet. Kept until a read reaches the Loop, for at most
/// `keptFor`, so it can never end the next night's sleep. Holds a time and a flag, no health values.
public struct ImUpRequest: Sendable, Equatable, Codable {
    public static let keptFor: TimeInterval = 6 * 3600

    public var tappedAt: Date
    /// A read tried to deliver it and didn't find the Loop.
    public var missedLoop: Bool

    public init(tappedAt: Date, missedLoop: Bool = false) {
        self.tappedAt = tappedAt
        self.missedLoop = missedLoop
    }

    /// A tap time in the future (the clock went back) isn't waiting.
    public func isWaiting(at now: Date) -> Bool {
        (0..<Self.keptFor).contains(now.timeIntervalSince(tappedAt))
    }
}

/// 03:00–12:00 local time: "I'm up" shows until last night is in, whether or not the Loop has been reached.
public enum MorningWindow {
    public static let from = 3
    public static let until = 12

    public static func contains(_ date: Date, in zone: TimeZone) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return (from..<until).contains(calendar.component(.hour, from: date))
    }
}
