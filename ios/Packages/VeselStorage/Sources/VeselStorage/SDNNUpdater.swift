import Foundation
import GRDB
import VeselCore

/// Works out each night's SDNN (`NightSDNN`, for Apple Health) once per read. A night is worked out again when its beats or
/// its sleep were stored at or after the last pass, so late beats for an old night count and a night without enough
/// recordings isn't tried every read. History is walked back from today, 14 nights with sleep per pass; a new method
/// version walks it again.
struct SDNNUpdater {
    /// The time of the last pass, unix seconds. Not uploaded.
    static let lastPassKey = "sdnn.lastPass"
    /// "<method version>:<oldest night done>". Not uploaded.
    static let fillKey = "sdnn.fill"
    static let nightsPerPass = 14

    func update(_ db: Database, now: Date) throws {
        var nights = Set<String>()
        if let lastPass = try Int64.fetchOne(db, sql: "SELECT CAST(value AS INTEGER) FROM setting WHERE key = ?", arguments: [Self.lastPassKey]) {
            // Sleep is stored under its result date (the night or the day after); its beats under the evening's or the morning's day.
            nights.formUnion(
                try String.fetchAll(
                    db,
                    sql: """
                        SELECT night FROM sleep_night AS s WHERE EXISTS (
                            SELECT 1 FROM band_ledger AS l WHERE l.stored_at >= ? AND (
                                (l.fetch_kind = ? AND l.day IN (date(s.night, '-1 day'), s.night))
                                OR (l.fetch_kind = ? AND l.day IN (s.night, date(s.night, '+1 day')))))
                        """,
                    arguments: [lastPass, FetchKind.ppi.rawValue, FetchKind.sleep.rawValue]))
        }

        let fill = try String.fetchOne(db, sql: "SELECT value FROM setting WHERE key = ?", arguments: [Self.fillKey])?
            .split(separator: ":", maxSplits: 1).map(String.init)
        let oldest = fill?.first == String(NightSDNN.version) ? fill?.last : nil
        let older = try String.fetchAll(
            db, sql: "SELECT night FROM sleep_night WHERE night < ? ORDER BY night DESC LIMIT ?",
            arguments: [oldest ?? "9999-12-31", Self.nightsPerPass])
        nights.formUnion(older)

        for night in nights {
            try recompute(db, night: night, now: now)
        }
        var settings = [Self.lastPassKey: String(now.unixSeconds)]
        if let last = older.last { settings[Self.fillKey] = "\(NightSDNN.version):\(last)" }
        for (key, value) in settings { try SettingRecord(key: key, value: value).upsert(db) }
    }

    private func recompute(_ db: Database, night: String, now: Date) throws {
        guard let sleep = try SleepNightRecord.fetchOne(db, key: night)?.model() else { return }
        let sessions = try StressInputs.sessions(
            db, where: "start_ts >= ? AND start_ts <= ?", arguments: [sleep.start.unixSeconds, sleep.end.unixSeconds])
        if let metric = NightSDNN.metric(sleep: sleep, sessions: sessions, computedAt: now) {
            try ComputedMetricRecord(metric).upsert(db)
        } else {
            try db.execute(sql: "DELETE FROM computed_metric WHERE kind = ? AND day = ?", arguments: [NightSDNN.kind, night])
        }
    }
}
