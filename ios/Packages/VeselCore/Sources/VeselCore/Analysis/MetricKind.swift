/// The `kind` of every number Vesel works out, as stored in `computed_metric`.
public enum MetricKind {
    public static let sleepAsleep = "sleep.asleep"
    public static let sleepInBed = "sleep.inBed"
    public static let sleepEfficiency = "sleep.efficiency"
    public static let sleepLowestHeartRate = "sleep.lowestHr"
    public static let recoveryStatus = "recovery.status"
    /// Per day: how many clean daytime readings there were, and how they were cleaned.
    public static let stressReadings = "stress.readings"
    /// Per day and hour: the highest stress level (0 to 100) of that hour's readings.
    public static let stressHourly = "stress.hourly"
    public static let stressHighMinutes = "stress.highMinutes"
    /// Per day: the most high-stress minutes within any 2 hours.
    public static let stressBusiestSpan = "stress.busiestSpan"
    /// The day's latest reading as a level.
    public static let stressNow = "stress.now"
    /// Per day, worked out on read and never stored: the day's average heart rate.
    public static let heartRateDayMean = "hr.dayMean"
    /// Per day, read from the daily summary on read and never stored as a metric: the day's steps.
    public static let steps = "activity.steps"

    public static func sleepStage(_ state: SleepState) -> String { "sleep.stage.\(state.rawValue)" }
}

/// Minutes as the screens write them: "6 h 05 m", "2 h", "45 m".
public enum DurationText {
    public static func hoursMinutes(minutes: Double) -> String {
        let total = Int(minutes.rounded())
        let hours = total / 60
        let rest = total % 60
        if hours == 0 { return "\(rest) m" }
        if rest == 0 { return "\(hours) h" }
        return "\(hours) h \(rest < 10 ? "0" : "")\(rest) m"
    }
}

enum NumberText {
    static func decimal(_ value: Double, _ places: Int) -> String {
        let text = String(format: "%.\(places)f", value)
        return text.hasPrefix("-") && Double(text) == 0 ? String(text.dropFirst()) : text
    }
}
