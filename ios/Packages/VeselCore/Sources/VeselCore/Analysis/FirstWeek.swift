import Foundation

/// The first week on Today (`firstWeek`, version 1): for each line still learning its normal, a check per night or day
/// that came in, an empty one for each the Loop missed, and how many more it needs. Worked out on read, never stored.
/// Counts what came in, never a streak: a missed night only leaves its check empty.
public struct FirstWeek: Sendable, Equatable {
    public static let method = "firstWeek"
    public static let version = 1
    /// Well-worn days calm needs: 7 for the stress baseline, then 7 counted days.
    public static let calmDays = StressThresholds.minimumDays + PersonalRange.minimumNights

    public enum Line: Sendable, Equatable { case recovery, sleep, calm }

    public enum Cell: Sendable, Equatable {
        case checked
        /// The Loop missed it.
        case missed
        /// Still to come.
        case ahead
    }

    public struct Row: Sendable, Equatable {
        public var line: Line
        public var cells: [Cell]
        /// Nights or days still needed.
        public var remaining: Int
        /// The morning the normal first shows; nil for calm, where wear decides it.
        public var normalFrom: DayKey?
        /// "2 more nights · Wed", "Your normal shows tomorrow", "about 9 more days".
        public var text: String
        public var explanation: Explanation

        public var checked: Int { cells.filter { $0 == .checked }.count }
        public var missed: Int { cells.filter { $0 == .missed }.count }
    }

    /// Recovery, sleep and calm, in that order; only the lines still learning.
    public var rows: [Row]

    /// `nights` have sleep or a Nightly Recharge; `sleepNights` a sleep result; `readings` is each day's clean stress
    /// readings. `shownNight` is the night Today shows, `lines` its lines and today's calm. Nil once every line has its
    /// normal.
    public static func make(
        nights: Set<DayKey>, sleepNights: Set<DayKey>, readings: [DayKey: Int], shownNight: DayKey?, today: DayKey, lines: DayLines
    ) -> FirstWeek? {
        var rows: [Row] = []
        if let shownNight, let first = nights.min() {
            if learning(lines.recovery.state, earlier: nights.filter { $0 < shownNight }.count) {
                rows.append(nightRow(.recovery, came: nights, from: first, through: shownNight, what: "nights"))
            }
            if learning(lines.sleep.state, earlier: sleepNights.filter { $0 < shownNight }.count) {
                rows.append(nightRow(.sleep, came: sleepNights, from: first, through: shownNight, what: "nights of sleep"))
            }
        }
        let worn = readings.filter { $0.value > 0 && $0.key < today }
        let wellWorn = Set(worn.filter { $0.value >= StressThresholds.minimumWindowsPerDay }.keys)
        if learning(lines.calm.state, earlier: wellWorn.count, needs: calmDays) {
            rows.append(calmRow(wellWorn: wellWorn, from: worn.keys.min(), through: today.adding(days: -1)))
        }
        return rows.isEmpty ? nil : FirstWeek(rows: rows)
    }

    /// A line still learning, or with no data for the day while too few came in before it.
    private static func learning(_ state: LineState, earlier: Int, needs: Int = PersonalRange.minimumNights) -> Bool {
        switch state {
        case .learning: true
        case .none: earlier < needs
        default: false
        }
    }

    private static func nightRow(_ line: Line, came: Set<DayKey>, from first: DayKey, through shown: DayKey, what: String) -> Row {
        let needs = PersonalRange.minimumNights
        var cells = days(from: first, through: shown).map { came.contains($0) ? Cell.checked : .missed }
        let checked = cells.filter { $0 == .checked }.count
        cells += Array(repeating: .ahead, count: max(needs - checked, 0))
        let remaining = max(needs - checked, 0)
        let normalFrom = shown.adding(days: needs + 1 - checked)
        let text =
            remaining == 0
            ? "Your normal shows tomorrow"
            : "\(remaining) more \(remaining == 1 ? "night" : "nights") · \(weekday(normalFrom))"
        let missed = cells.filter { $0 == .missed }.count
        return Row(
            line: line, cells: cells, remaining: remaining, normalFrom: normalFrom, text: text,
            explanation: Explanation(
                method: method, version: version,
                inputs: [.init(name: "nights", value: Double(checked), unit: "nights"), .init(name: "missed", value: Double(missed), unit: "nights")],
                text:
                    "Vesel needs \(needs) \(what) to learn your usual; \(checked) came in, \(missed) \(missed == 1 ? "was" : "were") missed. Your normal first shows on the morning after the \(needs)th."
            )
        )
    }

    private static func calmRow(wellWorn: Set<DayKey>, from first: DayKey?, through last: DayKey) -> Row {
        var cells = (first.map { days(from: $0, through: last) } ?? []).map { wellWorn.contains($0) ? Cell.checked : .missed }
        let checked = cells.filter { $0 == .checked }.count
        cells += Array(repeating: .ahead, count: max(calmDays - checked, 0))
        let remaining = max(calmDays - checked, 1)
        let missed = cells.filter { $0 == .missed }.count
        return Row(
            line: .calm, cells: cells, remaining: remaining, normalFrom: nil,
            text: "about \(remaining) more \(remaining == 1 ? "day" : "days")",
            explanation: Explanation(
                method: method, version: version,
                inputs: [.init(name: "days", value: Double(checked), unit: "days"), .init(name: "missed", value: Double(missed), unit: "days")],
                text:
                    "Vesel needs about \(calmDays) days with at least \(StressThresholds.minimumWindowsPerDay) clean readings each to learn your stress normal: \(StressThresholds.minimumDays) for your stress baseline, then \(PersonalRange.minimumNights) counted days. \(checked) came in, \(missed) had too few readings. Today counts once it is over."
            )
        )
    }

    private static func days(from first: DayKey, through last: DayKey) -> [DayKey] {
        var result: [DayKey] = []
        var day = first
        while day <= last {
            result.append(day)
            day = day.adding(days: 1)
        }
        return result
    }

    private static func weekday(_ day: DayKey) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let index = calendar.component(.weekday, from: day.start(in: calendar.timeZone))
        return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][index - 1]
    }
}
