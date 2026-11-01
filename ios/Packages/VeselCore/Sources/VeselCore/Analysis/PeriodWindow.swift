import Foundation

/// How many days a signal's page shows at once: the day itself, a week, 4 weeks or 3 months.
public enum PagePeriod: Int, CaseIterable, Sendable, Hashable {
    case day = 1, week = 7, month = 28, quarter = 90

    public var days: Int { rawValue }
}

/// The rolling windows a signal's page pages through: they end on today, today − n, today − 2n … (n = the period's days), so the
/// last window is always the most recent days and none starts or ends on a calendar edge. All of it is `DayKey` arithmetic, so a day
/// of 23 or 25 hours changes nothing.
public enum PeriodWindow {
    /// The last day of the window that holds `day`. A day after today is held by the window ending today.
    public static func end(holding day: DayKey, period: PagePeriod, today: DayKey) -> DayKey {
        guard day < today else { return today }
        let back = daysBetween(day, today) / period.days
        return today.adding(days: -back * period.days)
    }

    /// The first day of the window ending on `end`.
    public static func first(endingOn end: DayKey, period: PagePeriod) -> DayKey {
        end.adding(days: -(period.days - 1))
    }

    /// Every day of the window ending on `end`, oldest first.
    public static func days(endingOn end: DayKey, period: PagePeriod) -> [DayKey] {
        (0..<period.days).map { first(endingOn: end, period: period).adding(days: $0) }
    }

    public static func canPageLater(end: DayKey, today: DayKey) -> Bool { end < today }

    /// The ends of the windows a page swipes through, oldest first: from the window holding the earlier of `firstDay` and `holding`
    /// up to the one ending today. With no first day known yet, only the window holding `holding`.
    public static func pages(period: PagePeriod, holding: DayKey, firstDay: DayKey?, today: DayKey) -> [DayKey] {
        guard let firstDay else { return [end(holding: holding, period: period, today: today)] }
        let oldest = end(holding: min(firstDay, holding), period: period, today: today)
        return Array(sequence(first: today) { $0.adding(days: -period.days) }.prefix { $0 >= oldest }.reversed())
    }

    /// The end of the window one period later or earlier (`steps` of +1 or −1), never past today.
    public static func paged(end: DayKey, by steps: Int, period: PagePeriod, today: DayKey) -> DayKey {
        min(end.adding(days: steps * period.days), today)
    }

    /// The value that comes up most often; on a tie the newer day's wins. Nil for no values.
    public static func mostFrequent<Value: Hashable>(_ values: [(day: DayKey, value: Value)]) -> Value? {
        var counts: [Value: (count: Int, newest: DayKey)] = [:]
        for entry in values {
            let current = counts[entry.value]
            counts[entry.value] = ((current?.count ?? 0) + 1, max(current?.newest ?? entry.day, entry.day))
        }
        return counts.max { ($0.value.count, $0.value.newest) < ($1.value.count, $1.value.newest) }?.key
    }

    /// The plain average of the values there are; nil for none.
    public static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private static func daysBetween(_ first: DayKey, _ last: DayKey) -> Int {
        let utc = TimeZone(identifier: "UTC")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.dateComponents([.day], from: first.start(in: utc), to: last.start(in: utc)).day ?? 0
    }
}
