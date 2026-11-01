import Foundation

/// One day's three lines, with the numbers the week charts plot. What each line was judged against is in its `normal`.
public struct DayLines: Sendable, Equatable {
    public var recovery: LineVerdict
    public var sleep: LineVerdict
    public var calm: LineVerdict
    /// Polar's 1 to 6.
    public var indicator: Int?
    public var asleepMinutes: Double?
    /// Nil for a day without enough clean readings to count.
    public var highMinutes: Double?

    public static let empty = DayLines(
        recovery: InRange.recovery(status: nil, earlierNights: 0), sleep: InRange.sleep(nil), calm: InRange.calm(minutes: nil, previous: [])
    )

    public init(
        recovery: LineVerdict, sleep: LineVerdict, calm: LineVerdict,
        indicator: Int? = nil, asleepMinutes: Double? = nil, highMinutes: Double? = nil
    ) {
        self.recovery = recovery
        self.sleep = sleep
        self.calm = calm
        self.indicator = indicator
        self.asleepMinutes = asleepMinutes
        self.highMinutes = highMinutes
    }
}
