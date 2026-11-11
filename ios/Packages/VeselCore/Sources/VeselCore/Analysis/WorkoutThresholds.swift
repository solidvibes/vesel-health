import Foundation

/// Every number that decides how a workout is labelled and how its route is read, in one place.
public enum WorkoutThresholds {
    /// An average speed above this over the route is cycling, else running.
    public static let guessSpeedKmh = 13.0
    /// A guess from time of day looks at workouts starting this close to the same time of day.
    public static let guessWindowHours = 2.0
    /// … over this many days before.
    public static let guessHistoryDays = 90
    /// Route points less exact than this are dropped.
    public static let routeAccuracyMeters = 25.0
    /// A route stops by itself after this long.
    public static let routeMaxHours = 6.0
    /// A route covering less of the workout than this shows no speed and isn't used to guess.
    public static let routeMinCoverage = 0.5
    /// One route point kept every this many seconds.
    public static let routePointSeconds = 5.0
}
