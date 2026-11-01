import Foundation
import GRDB
import VeselCore

/// How much 24/7 data the band delivered in one local hour. Counts only, no health values.
public struct BandDataHour: Sendable, Equatable {
    public var day: DayKey
    public var hour: Int
    public var ppiSessions: Int
    public var ppiIntervals: Int
    /// Intervals the band marked with a blocker or without skin contact.
    public var ppiFlagged: Int
    public var hrSamples: Int

    public init(day: DayKey, hour: Int, ppiSessions: Int, ppiIntervals: Int, ppiFlagged: Int, hrSamples: Int) {
        self.day = day
        self.hour = hour
        self.ppiSessions = ppiSessions
        self.ppiIntervals = ppiIntervals
        self.ppiFlagged = ppiFlagged
        self.hrSamples = hrSamples
    }
}

extension AppDatabase {
    /// Per local hour from the start of `first` through the end of `last`, only hours with any data.
    public func bandDataReport(from first: DayKey, through last: DayKey, timeZone: TimeZone) async throws -> [BandDataHour] {
        let start = first.start(in: timeZone).unixSeconds
        let end = last.adding(days: 1).start(in: timeZone).unixSeconds
        let (sessions, hrTimes) = try await writer.read { db in
            let sessions = try Row.fetchAll(
                db,
                sql: """
                    SELECT s.start_ts AS ts, COUNT(p.ts_ms) AS intervals,
                           COALESCE(SUM(p.blocker OR NOT p.skin_contact), 0) AS flagged
                    FROM ppi_session s LEFT JOIN ppi_sample p ON p.session_id = s.id
                    WHERE s.start_ts >= ? AND s.start_ts < ?
                    GROUP BY s.id
                    """, arguments: [start, end]
            )
            .map { (ts: $0["ts"] as Int64, intervals: $0["intervals"] as Int, flagged: $0["flagged"] as Int) }
            let hrTimes = try Int64.fetchAll(db, sql: "SELECT ts FROM hr_sample WHERE ts >= ? AND ts < ?", arguments: [start, end])
            return (sessions, hrTimes)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        struct Key: Hashable { var day: DayKey; var hour: Int }
        func key(_ ts: Int64) -> Key {
            let date = Date(unixSeconds: ts)
            return Key(day: DayKey(date, in: timeZone), hour: calendar.component(.hour, from: date))
        }

        var hours: [Key: BandDataHour] = [:]
        func entry(_ key: Key) -> BandDataHour {
            hours[key] ?? BandDataHour(day: key.day, hour: key.hour, ppiSessions: 0, ppiIntervals: 0, ppiFlagged: 0, hrSamples: 0)
        }
        for session in sessions {
            let k = key(session.ts)
            var hour = entry(k)
            hour.ppiSessions += 1
            hour.ppiIntervals += session.intervals
            hour.ppiFlagged += session.flagged
            hours[k] = hour
        }
        for ts in hrTimes {
            let k = key(ts)
            var hour = entry(k)
            hour.hrSamples += 1
            hours[k] = hour
        }
        return hours.values.sorted { ($0.day, $0.hour) < ($1.day, $1.hour) }
    }
}
