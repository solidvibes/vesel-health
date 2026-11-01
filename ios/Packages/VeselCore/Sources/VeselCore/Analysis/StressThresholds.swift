import Foundation

/// Every number that decides what counts as stress, in one place.
/// These are the plan's starting values, to be revisited once the owner's week of band data report counts is in.
public enum StressThresholds {
    // Cleaning
    public static let minimumIntervalMs = 300
    public static let maximumIntervalMs = 2000
    /// An interval differing from the previous valid one by more than this share is an artefact.
    public static let maximumJump = 0.20

    // Windows
    public static let windowSeconds = 60.0
    public static let minimumIntervals = 30
    /// Only readings from these local hours count: night readings are sleep, not stress.
    public static let daytimeHours = 6..<22
    /// Exercise: a heart rate above resting + this share of the reserve (max − resting).
    public static let activityReserveShare = 0.4
    /// A heart-rate reading this close to a window decides whether it was exercise.
    public static let activityMarginSeconds = 120.0

    // Baseline
    public static let baselineDays = 14
    public static let baselinePercentile = 0.8
    public static let floorPercentile = 0.05
    public static let minimumDays = 7
    public static let minimumWindowsPerDay = 10

    // Levels, 0 to 100
    public static let moderateFrom = 34.0
    public static let highFrom = 67.0

    // Minutes and "now"
    public static let longestCountedGap: TimeInterval = 15 * 60
    public static let nowFor: TimeInterval = 30 * 60
    /// The span the long-high-stress alert looks at.
    public static let busiestSpan: TimeInterval = 2 * 3600
    /// The calm line stays inside up to at least this many high-stress minutes, however calm your usual days are.
    public static let calmAllowanceMinutes = 15.0
}
