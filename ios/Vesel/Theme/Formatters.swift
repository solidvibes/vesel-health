import Foundation
import VeselCore

/// Dates and times as the screens write them, always in the zone Vesel's clock uses.
enum Formatters {
    static func time(_ date: Date, zone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(time: .shortened, timeZone: zone))
    }

    /// "Sun, Oct 25" in the phone's locale order
    static func day(_ day: DayKey, zone: TimeZone) -> String {
        day.start(in: zone).formatted(Date.FormatStyle(timeZone: zone).weekday(.abbreviated).day().month(.abbreviated))
    }

    /// "25 Oct"
    static func shortDay(_ day: DayKey, zone: TimeZone) -> String {
        day.start(in: zone).formatted(Date.FormatStyle(timeZone: zone).day().month(.abbreviated))
    }

    /// "Monday night, October 26": the evening a night began, for the night that ends on `night`.
    static func nightEvening(_ night: DayKey, zone: TimeZone) -> String {
        let evening = night.adding(days: -1)
        let date = evening.start(in: zone).formatted(Date.FormatStyle(timeZone: zone).month(.wide).day())
        return "\(weekday(evening, zone: zone)) night, \(date)"
    }

    /// "S", "M"… for the recovery week.
    static func weekdayLetter(_ day: DayKey, zone: TimeZone) -> String {
        String(day.start(in: zone).formatted(Date.FormatStyle(timeZone: zone).weekday(.narrow)))
    }

    static func weekday(_ day: DayKey, zone: TimeZone) -> String {
        day.start(in: zone).formatted(Date.FormatStyle(timeZone: zone).weekday(.wide))
    }

    /// "14:00–15:00" for the hour starting at 14.
    static func hourRange(_ hour: Int) -> String {
        String(format: "%02d:00–%02d:00", hour, hour + 1)
    }

    /// "03:12": the time on a 24-hour clock, whatever the phone's own setting is.
    static func clock(_ date: Date, zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return String(format: "%02d:%02d", calendar.component(.hour, from: date), calendar.component(.minute, from: date))
    }

    /// "06", "14": the hour on a 24-hour axis, whatever the phone's own setting is.
    static func hourLabel(_ date: Date, zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return String(format: "%02d", calendar.component(.hour, from: date))
    }

    /// "9 hours ago", "yesterday": how long before `now`, as Loop & settings writes its other times; "just now" under a minute.
    static func ago(_ date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 60 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// "8,850": a step count with the phone's own grouping.
    static func steps(_ value: Int) -> String { value.formatted(.number.grouping(.automatic)) }

    static func whole(_ value: Double) -> String { String(Int(value.rounded())) }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
