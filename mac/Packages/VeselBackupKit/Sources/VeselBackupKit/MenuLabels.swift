import Foundation

public struct CountLine: Sendable, Equatable, Identifiable {
    public let label: String
    public let count: Int

    public init(label: String, count: Int) {
        self.label = label
        self.count = count
    }

    public var id: String { label }
}

public enum MenuLabels {
    static let known: [(table: String, label: String)] = [
        ("sleep_night", "nights of sleep"),
        ("nightly_recharge", "Nightly Recharge nights"),
        ("hr_sample", "heart-rate readings"),
        ("ppi_sample", "beat-to-beat readings"),
        ("skin_temp_sample", "skin temperature readings"),
        ("activity_day", "days of activity"),
        ("workout", "workouts"),
        ("workout_route", "workout routes"),
        ("alert_event", "alerts"),
    ]

    /// Known tables in a fixed order, everything else summed as "other rows". Zero counts are left out.
    public static func lines(for counts: [String: Int]) -> [CountLine] {
        let knownTables = Set(known.map(\.table))
        var lines = known.compactMap { entry -> CountLine? in
            guard let count = counts[entry.table], count > 0 else { return nil }
            return CountLine(label: entry.label, count: count)
        }
        let other = counts.filter { !knownTables.contains($0.key) }.values.reduce(0, +)
        if other > 0 {
            lines.append(CountLine(label: "other rows", count: other))
        }
        return lines
    }

    /// "today 07:42", "yesterday 23:10", or "3 Oct 07:42".
    public static func lastBackup(_ date: Date, now: Date, calendar: Calendar) -> String {
        let style = Date.FormatStyle(locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone)
        let time = date.formatted(style.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        if calendar.isDate(date, inSameDayAs: now) {
            return "today \(time)"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "yesterday \(time)"
        }
        let day = date.formatted(style.day().month(.abbreviated))
        return "\(day) \(time)"
    }
}
