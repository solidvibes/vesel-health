import Foundation

/// What a workout is called and why: the owner's fix, the Loop's sport, a guess from speed or time of day, or nothing.
public struct WorkoutLabel: Sendable, Equatable {
    public enum Source: String, Sendable {
        case owner, band, speed, timeOfDay, none
    }

    /// Nil means "Workout".
    public var sport: WorkoutSport?
    public var source: Source
    /// The owner said "Not a workout".
    public var hidden: Bool

    public init(sport: WorkoutSport?, source: Source, hidden: Bool) {
        self.sport = sport
        self.source = source
        self.hidden = hidden
    }

    /// First match: the owner's fix, the Loop's sport (shown even if it isn't one of `sports`), speed over a route covering
    /// at least half the workout, the sport most often done within 2 hours of this time of day over the 90 days before
    /// (from workouts the Loop or the owner named), else none. Guesses use only `sports`; ties go in `WorkoutSport.guessOrder`.
    public static func make(
        workout: Workout, choice: WorkoutChoice?, route: WorkoutRouteSummary?, history: [(start: Date, sport: WorkoutSport)],
        sports: Set<WorkoutSport>, zone: TimeZone
    ) -> WorkoutLabel {
        let hidden = choice?.hidden ?? false
        if let sport = choice?.sport { return WorkoutLabel(sport: sport, source: .owner, hidden: hidden) }
        if let sport = workout.bandSportId.flatMap(WorkoutSport.init(bandSportId:)) {
            return WorkoutLabel(sport: sport, source: .band, hidden: hidden)
        }
        if let route, route.coversEnough, let speed = route.averageSpeedKmh {
            let sport: WorkoutSport = speed > WorkoutThresholds.guessSpeedKmh ? .cycling : .running
            if sports.contains(sport) { return WorkoutLabel(sport: sport, source: .speed, hidden: hidden) }
        }
        if let sport = byTimeOfDay(workout.start, history: history, sports: sports, zone: zone) {
            return WorkoutLabel(sport: sport, source: .timeOfDay, hidden: hidden)
        }
        return WorkoutLabel(sport: nil, source: .none, hidden: hidden)
    }

    private static func byTimeOfDay(_ start: Date, history: [(start: Date, sport: WorkoutSport)], sports: Set<WorkoutSport>, zone: TimeZone)
        -> WorkoutSport?
    {
        let earliest = start.addingTimeInterval(-Double(WorkoutThresholds.guessHistoryDays) * 86400)
        let window = WorkoutThresholds.guessWindowHours * 60
        let minute = minuteOfDay(start, zone: zone)
        var counts: [WorkoutSport: Int] = [:]
        for earlier in history where earlier.start >= earliest && earlier.start < start && sports.contains(earlier.sport) {
            let apart = abs(minuteOfDay(earlier.start, zone: zone) - minute)
            if min(apart, 24 * 60 - apart) <= window { counts[earlier.sport, default: 0] += 1 }
        }
        guard let most = counts.values.max() else { return nil }
        return WorkoutSport.guessOrder.first { counts[$0] == most }
    }

    private static func minuteOfDay(_ date: Date, zone: TimeZone) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }
}
