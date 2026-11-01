import Foundation

public protocol VeselClock: Sendable {
    var now: Date { get }
    var timeZone: TimeZone { get }
}

extension VeselClock {
    public var today: DayKey { DayKey(now, in: timeZone) }
}

public struct SystemClock: VeselClock {
    public init() {}
    public var now: Date { Date() }
    public var timeZone: TimeZone { .current }
}

public struct FixedClock: VeselClock {
    public var now: Date
    public var timeZone: TimeZone

    public init(now: Date, timeZone: TimeZone) {
        self.now = now
        self.timeZone = timeZone
    }
}
