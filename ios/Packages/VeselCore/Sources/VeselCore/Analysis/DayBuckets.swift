import Foundation

/// The items of one stretch of a day.
public struct DayBucket<Element> {
    public var day: DayKey
    public var start: Date
    public var end: Date
    public var items: [Element]
}

/// Groups timed items into fixed stretches of a day. Stretches count in elapsed time from the start of the zone's day and never
/// cross midnight, so the day clocks go back has a short or long last stretch. Empty stretches are left out.
public enum DayBuckets {
    private struct Slot: Hashable { var day: DayKey; var index: Int }

    /// `minutes` nil gives one bucket per calendar day of `zone`. Oldest first.
    public static func group<Element>(_ items: [Element], time: (Element) -> Date, minutes: Int?, zone: TimeZone) -> [DayBucket<Element>] {
        var bySlot: [Slot: [Element]] = [:]
        for item in items {
            let moment = time(item)
            let day = DayKey(moment, in: zone)
            let index = minutes.map { Int(moment.timeIntervalSince(day.start(in: zone)) / Double($0 * 60)) } ?? 0
            bySlot[Slot(day: day, index: index), default: []].append(item)
        }
        return bySlot.map { slot, items in
            let dayStart = slot.day.start(in: zone)
            let nextDay = slot.day.adding(days: 1).start(in: zone)
            guard let minutes else { return DayBucket(day: slot.day, start: dayStart, end: nextDay, items: items) }
            let start = dayStart.addingTimeInterval(Double(slot.index * minutes * 60))
            return DayBucket(day: slot.day, start: start, end: min(start.addingTimeInterval(Double(minutes * 60)), nextDay), items: items)
        }.sorted { $0.start < $1.start }
    }

    /// A wall-clock time in `zone`: "14:00".
    public static func clock(_ date: Date, zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}
