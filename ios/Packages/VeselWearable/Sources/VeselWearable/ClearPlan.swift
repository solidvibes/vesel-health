import Foundation
import VeselCore

/// Which days of a band data type are safe to clear off the band. Pure: no band, no database.
public enum ClearPlan {
    /// The latest day D such that every day from the last clear through D is stored for each of the type's
    /// fetch kinds (see `isStored`). Never today or yesterday. Nil when nothing is safe to clear.
    public static func lastSafeDay(for type: StoredDataType, ledger: [LedgerEntry], today: DayKey, timeZone: TimeZone) -> DayKey? {
        let kinds = Set(type.fetchKinds)
        let rows = ledger.filter { kinds.contains($0.kind) }
        var byDay: [DayKey: [FetchKind: LedgerEntry]] = [:]
        for row in rows {
            byDay[row.day, default: [:]][row.kind] = row
        }
        let lastCleared = rows.filter { $0.deletedFromBandAt != nil }.map(\.day).max()
        guard var day = lastCleared.map({ $0.adding(days: 1) }) ?? rows.map(\.day).min() else { return nil }
        let cap = today.adding(days: -2)
        var safe: DayKey?
        while day <= cap {
            let stored = kinds.allSatisfy { kind in
                byDay[day]?[kind].map { isStored($0, timeZone: timeZone) } ?? false
            }
            guard stored else { break }
            safe = day
            day = day.adding(days: 1)
        }
        return safe
    }

    /// The earliest day of the ledger's kind that is neither cleared nor stored yet. The next sync reads from there,
    /// so an empty day gets the second read it needs instead of blocking clearing forever.
    public static func firstUnsettledDay(in ledger: [LedgerEntry], timeZone: TimeZone) -> DayKey? {
        let lastCleared = ledger.filter { $0.deletedFromBandAt != nil }.map(\.day).max()
        return
            ledger
            .filter { row in lastCleared.map { row.day > $0 } ?? true }
            .filter { !isStored($0, timeZone: timeZone) }
            .map(\.day)
            .min()
    }

    /// Stored after the day ended (after the band's midnight flush). A day that read empty counts only once it read
    /// empty on two syncs after it ended, the latest at least an hour after the one before: the SDK reports some failed
    /// reads as "no data", and one empty read can't tell those apart from a day the band wasn't worn.
    static func isStored(_ row: LedgerEntry, timeZone: TimeZone) -> Bool {
        let dayEnd = row.day.adding(days: 1).start(in: timeZone)
        guard row.storedAt >= dayEnd else { return false }
        if row.sampleCount > 0 { return true }
        guard let earlier = row.earlierEmptyAt else { return false }
        return earlier >= dayEnd && row.storedAt.timeIntervalSince(earlier) >= emptyReadsApart
    }

    static let emptyReadsApart: TimeInterval = 60 * 60

    /// The `until` the Polar SDK expects for clearing through `day`: it compares `yyyyMMdd` in UTC and deletes
    /// up to and including that date, so noon UTC names `day` whatever the phone's time zone.
    public static func until(_ day: DayKey) -> Date {
        day.start(in: TimeZone(identifier: "UTC")!).addingTimeInterval(12 * 3600)
    }
}
