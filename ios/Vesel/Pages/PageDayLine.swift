import Foundation
import VeselCore

/// The line under a page's title.
enum PageDayLine {
    /// "Last night" for today's night, else "Monday night, October 26".
    static func night(_ day: DayKey, shown: DayKey?, today: DayKey, zone: TimeZone) -> String {
        day == today ? "Last night" : Formatters.nightEvening(shown ?? day, zone: zone)
    }

    /// "Today" or "Tue, Oct 27".
    static func day(_ day: DayKey, today: DayKey, zone: TimeZone) -> String {
        day == today ? "Today" : Formatters.day(day, zone: zone)
    }
}
