import Foundation
import GRDB
import VeselCore

/// Works out the stress numbers for days that have beat-to-beat data, and for the later days whose 14-day baseline
/// they feed. The analysis lives in VeselCore; this gathers the beats and heart rates and writes the results.
struct StressUpdater {
    /// A day this recent is always recomputed: the band may still be delivering it.
    static let recentDays = 3

    let clock: any VeselClock

    /// Recent days with beats, days with beats but no numbers yet, days whose beats or heart rates were stored after
    /// their numbers (a sync re-read them), days whose workouts or the owner's fixes to them changed after their numbers,
    /// and days stored under an older method version.
    func touchedDays(_ db: Database, today: DayKey) throws -> Set<DayKey> {
        let withBeats = try StressInputs.daysWithBeats(db)
        let recent = today.adding(days: -(Self.recentDays - 1))
        var touched = withBeats.filter { $0 >= recent }
        let missing = try String.fetchAll(
            db,
            sql: """
                SELECT DISTINCT day FROM ppi_session WHERE day NOT IN (SELECT day FROM computed_metric WHERE kind = ?)
                """, arguments: [MetricKind.stressReadings])
        touched.formUnion(missing.compactMap(DayKey.init))
        let late = try String.fetchAll(
            db,
            sql: """
                SELECT DISTINCT ledger.day FROM band_ledger ledger
                JOIN computed_metric metric ON metric.kind = ? AND metric.hour IS NULL AND metric.day = ledger.day
                WHERE ledger.fetch_kind IN (?, ?) AND ledger.stored_at > metric.computed_at
                    AND ledger.day IN (SELECT day FROM ppi_session)
                """, arguments: [MetricKind.stressReadings, FetchKind.ppi.rawValue, FetchKind.heartRate.rawValue])
        touched.formUnion(late.compactMap(DayKey.init))
        touched.formUnion(try workoutDays(db, withBeats: withBeats))
        let stale = try String.fetchAll(
            db, sql: "SELECT DISTINCT day FROM computed_metric WHERE method = ? AND method_version <> ?",
            arguments: [Stress.method, Stress.version]
        )
        touched.formUnion(stale.compactMap(DayKey.init))
        return touched
    }

    /// Days with beats and numbers that a workout overlaps, where the workout or the owner's fix changed after the numbers.
    private func workoutDays(_ db: Database, withBeats: Set<DayKey>) throws -> Set<DayKey> {
        let computed = Dictionary(
            uniqueKeysWithValues: try Row.fetchAll(
                db, sql: "SELECT day, computed_at FROM computed_metric WHERE kind = ? AND hour IS NULL", arguments: [MetricKind.stressReadings]
            ).compactMap { row in DayKey(row["day"] as String).map { ($0, row["computed_at"] as Int64) } })
        var days: Set<DayKey> = []
        let zone = clock.timeZone
        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT w.start_at, w.end_at, MAX(w.stored_at, IFNULL(c.chosen_at, 0)) AS changed_at
                FROM workout AS w LEFT JOIN workout_choice AS c ON c.session = w.session
                """)
        {
            let changedAt: Int64 = row["changed_at"]
            let startAt: Int64 = row["start_at"]
            let endAt: Int64 = row["end_at"]
            var day = DayKey(Date(unixSeconds: startAt), in: zone)
            // A workout ending at midnight doesn't reach the next day (the same overlap `StressInputs` uses).
            let last = DayKey(Date(unixSeconds: max(startAt, endAt - 1)), in: zone)
            while day <= last {
                if withBeats.contains(day), let computedAt = computed[day], computedAt < changedAt { days.insert(day) }
                day = day.adding(days: 1)
            }
        }
        return days
    }

    /// Recomputes `days` and every later day within 14 days that has beats, since their baseline includes these.
    func recompute(_ db: Database, days: Set<DayKey>, now: Date) throws -> Set<DayKey> {
        guard !days.isEmpty else { return [] }
        let withBeats = try StressInputs.daysWithBeats(db)
        let affected = withBeats.filter { day in
            days.contains(day) || days.contains { $0 < day && day <= $0.adding(days: StressThresholds.baselineDays) }
        }
        guard let first = affected.min(), let last = affected.max() else { return [] }

        let limits = try StressInputs.ActivityLimits(db)

        var windowsByDay: [DayKey: (windows: [StressWindow], counts: StressCounts)] = [:]
        var day = first.adding(days: -StressThresholds.baselineDays)
        while day <= last {
            if withBeats.contains(day) {
                var found = Stress.windows(
                    sessions: try StressInputs.sessions(db, day: day),
                    heartRates: try StressInputs.heartRates(db, day: day, zone: clock.timeZone),
                    activityHeartRate: limits.heartRate(on: day),
                    workouts: try StressInputs.workouts(db, day: day, zone: clock.timeZone)
                )
                // A reading can't be from the future (the clock can be moved back in the Simulator).
                found.windows.removeAll { $0.start > now }
                found.counts.windows = found.windows.count
                windowsByDay[day] = found
            }
            day = day.adding(days: 1)
        }
        let values = windowsByDay.mapValues { $0.windows.map(\.value) }

        for day in affected.sorted() {
            guard let found = windowsByDay[day] else { continue }
            let outcome = StressBaseline.make(before: day, valuesByDay: values)
            let metrics = Stress.metrics(day: day, windows: found.windows, counts: found.counts, baseline: outcome, computedAt: now)
            for metric in metrics { try ComputedMetricRecord(metric).upsert(db) }
            // Unchanged numbers keep their old time; worked out again now, they count as newer than the readings and workouts they used.
            let workoutsChangedAt = try StressInputs.workoutsChangedAt(db, day: day, zone: clock.timeZone) ?? 0
            try db.execute(
                sql: """
                    UPDATE computed_metric SET computed_at = ? WHERE kind = ? AND day = ? AND hour IS NULL
                        AND computed_at < MAX(IFNULL((SELECT MAX(stored_at) FROM band_ledger WHERE day = ? AND fetch_kind IN (?, ?)), 0), ?)
                    """,
                arguments: [
                    now.unixSeconds, MetricKind.stressReadings, day.description, day.description, FetchKind.ppi.rawValue, FetchKind.heartRate.rawValue,
                    workoutsChangedAt,
                ])
            // An hour or total that is no longer produced goes too.
            let kept = Set(metrics.map { "\($0.kind)/\($0.hour ?? -1)" })
            for row in try Row.fetchAll(
                db, sql: "SELECT kind, hour FROM computed_metric WHERE day = ? AND method = ?", arguments: [day.description, Stress.method])
            {
                let kind: String = row["kind"]
                let hour: Int? = row["hour"]
                guard !kept.contains("\(kind)/\(hour ?? -1)") else { continue }
                try db.execute(
                    sql: "DELETE FROM computed_metric WHERE day = ? AND kind = ? AND ifnull(hour, -1) = ?",
                    arguments: [day.description, kind, hour ?? -1]
                )
            }
        }
        return affected
    }
}
