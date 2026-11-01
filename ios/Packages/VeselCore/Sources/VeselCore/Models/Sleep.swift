import Foundation

public struct SleepNight: Sendable, Equatable {
    public var night: DayKey
    public var start: Date
    public var end: Date
    public var goalMinutes: Int?
    public var phases: [SleepPhase]

    public init(night: DayKey, start: Date, end: Date, goalMinutes: Int?, phases: [SleepPhase]) {
        self.night = night
        self.start = start
        self.end = end
        self.goalMinutes = goalMinutes
        self.phases = phases
    }

    /// The stage at a moment, counted as `SleepSummary` counts it. Nil outside start...end.
    public func state(at date: Date) -> SleepState? {
        guard date >= start, date <= end else { return nil }
        if phases.isEmpty { return .unknown }
        let elapsed = date.timeIntervalSince(start)
        let sorted = phases.sorted { $0.secondsFromStart < $1.secondsFromStart }
        return sorted.last { TimeInterval(max($0.secondsFromStart, 0)) <= elapsed }?.state ?? .wake
    }
}

public struct SleepPhase: Sendable, Equatable, Codable {
    public var secondsFromStart: Int
    public var state: SleepState

    public init(secondsFromStart: Int, state: SleepState) {
        self.secondsFromStart = secondsFromStart
        self.state = state
    }
}

public enum SleepState: String, Sendable, Codable {
    case wake, rem, light, deep, unknown
}
