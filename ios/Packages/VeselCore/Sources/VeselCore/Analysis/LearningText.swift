import Foundation

/// The one line every screen shows while a usual range is still being learned. Without a count on the first night: never "0 of 7".
public enum LearningText {
    /// `earlier` = nights before the one shown that count towards the usual range.
    public static func nights(_ earlier: Int) -> String {
        line("Your usual range appears after \(PersonalRange.minimumNights) nights", earlier: earlier, of: PersonalRange.minimumNights)
    }

    /// `earlier` = days before the one shown that count towards the stress baseline.
    public static func days(_ earlier: Int) -> String {
        line("Your stress levels appear after \(StressThresholds.minimumDays) days", earlier: earlier, of: StressThresholds.minimumDays)
    }

    /// `earlier` = days before the one shown that count towards the usual range of daily steps.
    public static func usualDays(_ earlier: Int) -> String {
        line("Your usual range appears after \(PersonalRange.minimumNights) days", earlier: earlier, of: PersonalRange.minimumNights)
    }

    /// Heart fitness is worked out on the 1st; `next` is the 1st it will be worked out on. No counts: nothing to watch day by day.
    public static func fitness(next: DayKey) -> String {
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return
            "Heart fitness is worked out on the 1st of each month, once a month has \(FitnessAge.minimumNights) nights and \(FitnessAge.minimumWornDays) days with your Loop. Next: \(next.day) \(months[next.month - 1])."
    }

    private static func line(_ text: String, earlier: Int, of total: Int) -> String {
        earlier > 0 ? "\(text) · \(earlier) of \(total)" : text
    }
}
