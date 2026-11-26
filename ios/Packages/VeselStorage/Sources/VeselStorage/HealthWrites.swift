import Foundation
import GRDB
import VeselCore

/// What Vesel last wrote to Apple Health for a unit.
public struct HealthWritten: Sendable, Equatable {
    public var digest: String
    public var syncVersion: Int64
}

/// A unit's items, read with the time they were read at (its `written_at` once saved) and what was written before.
public struct HealthBatchRead: Sendable {
    public var batch: HealthBatch
    public var snapshot: Date
    public var last: HealthWritten?
}

/// The switch and how the last write went, for Loop & settings.
public struct HealthStatus: Sendable, Equatable {
    public var isOn: Bool
    public var lastRun: HealthRun?

    public init(isOn: Bool, lastRun: HealthRun?) {
        self.isOn = isOn
        self.lastRun = lastRun
    }
}

/// The bookkeeping for writing to Apple Health (`health_write`, one row per unit). Not health data, never uploaded.
/// A unit is pending when it has data and no row, its mapping changed, one of its sources was stored at or after its
/// `written_at`, it has a row and no data any more, or (heart rate and energy days) whether Workouts are allowed changed
/// since it was written. The writer never runs beside a read, so every `stored_at` it can see
/// is no later than its snapshot, and a later read always stamps the same second or later.
extension AppDatabase {
    /// "on" while Vesel writes to Health. Not uploaded.
    public static let healthWriteKey = "health.write"
    /// JSON `HealthRun`. Not uploaded.
    public static let healthLastRunKey = "health.lastRun"

    /// "on" when heart rate or energy days were last all written with Workouts allowed (their readings and energy then go
    /// with the workouts). Not uploaded.
    static func healthWithWorkoutsKey(_ kind: HealthKind) -> String { "health.withWorkouts.\(kind.rawValue)" }
    /// The day kinds that are written differently when Workouts are allowed.
    static let kindsFollowingWorkouts: [HealthKind] = [.heartRate, .energy]

    /// Turning on forgets every earlier write, so everything is written again (same ids, so nothing doubles); turning off
    /// keeps how the last write went.
    public func setHealthWrite(_ on: Bool) async throws {
        try await writer.write { db in
            if on {
                try db.execute(sql: "DELETE FROM health_write")
                let keys = [Self.healthLastRunKey] + Self.kindsFollowingWorkouts.map(Self.healthWithWorkoutsKey)
                try db.execute(sql: "DELETE FROM setting WHERE key IN (\(databaseQuestionMarks(count: keys.count)))", arguments: StatementArguments(keys))
            }
            try SettingRecord(key: Self.healthWriteKey, value: on ? "on" : "off").upsert(db)
        }
    }

    public func healthStatus() async throws -> HealthStatus {
        try await writer.read { try Self.healthStatus($0) }
    }

    /// Only the switch and the last run: nothing over all history.
    public func observeHealthStatus() -> some AsyncSequence<HealthStatus, any Error> {
        ValueObservation.tracking { db in try Self.healthStatus(db) }.removeDuplicates().values(in: writer)
    }

    static func healthStatus(_ db: Database) throws -> HealthStatus {
        let values = Dictionary(
            uniqueKeysWithValues: try Row.fetchAll(
                db, sql: "SELECT key, value FROM setting WHERE key IN (?, ?)", arguments: [healthWriteKey, healthLastRunKey]
            ).map { ($0["key"] as String, $0["value"] as String) })
        return HealthStatus(
            isOn: values[healthWriteKey] == "on",
            lastRun: try values[healthLastRunKey].map { try StoredJSON.decode(HealthRun.self, from: $0) }
        )
    }

    public func saveHealthRun(_ run: HealthRun) async throws {
        try await setSettings([Self.healthLastRunKey: try StoredJSON.encode(run)])
    }

    public func hasHealthWrites() async throws -> Bool {
        try await writer.read { try Bool.fetchOne($0, sql: "SELECT EXISTS (SELECT 1 FROM health_write)") ?? false }
    }

    /// Every heart rate and energy day of `kinds` was written with Workouts allowed or not: remembers which.
    public func healthDaysWritten(kinds: Set<HealthKind>, withWorkouts: Bool) async throws {
        let value = withWorkouts ? "on" : "off"
        try await setSettings(
            Dictionary(uniqueKeysWithValues: Self.kindsFollowingWorkouts.filter(kinds.contains).map { (Self.healthWithWorkoutsKey($0), value) }))
    }

    /// Units of `kinds` to write, newest first. A day is cut in `zone` where a workout crosses it.
    public func pendingHealthUnits(kinds: Set<HealthKind>, zone: TimeZone) async throws -> [HealthUnit] {
        try await writer.read { db in
            let workouts = kinds.contains(.workout)
            var pending: [HealthUnit] = []
            for kind in HealthKind.allCases where kinds.contains(kind) {
                let stamps = try Self.healthSources(db, kind, workouts: workouts, zone: zone)
                let written = Dictionary(
                    uniqueKeysWithValues: try Row.fetchAll(
                        db, sql: "SELECT unit, mapping_version, written_at FROM health_write WHERE kind = ?", arguments: [kind.rawValue]
                    ).map { ($0["unit"] as String, (version: $0["mapping_version"] as Int, writtenAt: $0["written_at"] as Int64)) })
                let regrouped = try Self.kindsFollowingWorkouts.contains(kind) && Self.writtenWithWorkouts(db, kind) != workouts
                for (key, stamp) in stamps {
                    let unit = HealthUnit(kind: kind, key: key)
                    guard let row = written[unit.id] else {
                        pending.append(unit)
                        continue
                    }
                    if regrouped || row.version != HealthMapping.version(kind) || stamp >= row.writtenAt { pending.append(unit) }
                }
                pending += written.keys.compactMap(HealthUnit.init(id:)).filter { stamps[$0.key] == nil }
            }
            return pending.sorted { ($0.date, $0.key, $1.kind.rawValue) > ($1.date, $1.key, $0.kind.rawValue) }
        }
    }

    private static func writtenWithWorkouts(_ db: Database, _ kind: HealthKind) throws -> Bool {
        try String.fetchOne(db, sql: "SELECT value FROM setting WHERE key = ?", arguments: [healthWithWorkoutsKey(kind)]) == "on"
    }

    /// Each unit of `kind` that has data, with the latest time one of its sources was stored or worked out. With Workouts
    /// allowed, a heart rate day also follows the workouts crossing it, and an energy day the workouts that started on it.
    private static func healthSources(_ db: Database, _ kind: HealthKind, workouts: Bool, zone: TimeZone) throws -> [String: Int64] {
        // Sleep is stored under its result date, so its ledger row is the night's or the next day's.
        func sleepStamp(_ night: String) -> String {
            "IFNULL((SELECT MAX(stored_at) FROM band_ledger WHERE fetch_kind = 'sleep' AND day IN (\(night), date(\(night), '+1 day'))), 0)"
        }
        let sql: String
        var arguments: StatementArguments = []
        switch kind {
        case .heartRate, .steps:
            sql = "SELECT day AS key, stored_at AS stamp FROM band_ledger WHERE fetch_kind = ? AND sample_count > 0"
            arguments = [kind == .heartRate ? FetchKind.heartRate.rawValue : FetchKind.activitySamples.rawValue]
        case .sleep:
            sql = "SELECT night AS key, \(sleepStamp("night")) AS stamp FROM sleep_night"
        case .restingHeartRate, .respiratoryRate, .hrv:
            sql = """
                SELECT day AS key, MAX(computed_at, \(sleepStamp("metric.day"))) AS stamp
                FROM computed_metric AS metric WHERE kind = ? AND hour IS NULL
                """
            arguments = [metricKind(kind)]
        case .energy:
            sql = """
                SELECT a.day AS key, IFNULL(l.stored_at, 0) AS stamp
                FROM activity_day AS a LEFT JOIN band_ledger AS l ON l.day = a.day AND l.fetch_kind = ?
                """
            arguments = [FetchKind.dailySummary.rawValue]
        case .workout:
            // Its fix, its route, its day's summary (its resting share) and the 24/7 heart rate of the days it spans (when it has
            // none of its own).
            sql = """
                SELECT w.session AS key, MAX(
                    w.stored_at, IFNULL(c.chosen_at, 0),
                    IFNULL((SELECT MAX(r.updated_at) FROM workout_route AS r WHERE r.started_at <= w.end_at AND r.started_at >= w.start_at - ?
                        AND IFNULL(r.ended_at, w.end_at) >= w.start_at), 0),
                    IFNULL((SELECT MAX(l.stored_at) FROM band_ledger AS l WHERE (l.fetch_kind = ? AND l.day = w.day)
                        OR (l.fetch_kind = ? AND l.day >= w.day AND l.day <= date(w.end_at + w.utc_offset_seconds, 'unixepoch'))), 0)) AS stamp
                FROM workout AS w LEFT JOIN workout_choice AS c ON c.session = w.session
                WHERE IFNULL(c.hidden, 0) = 0
                """
            arguments = [Int64(WorkoutThresholds.routeMaxHours * 3600), FetchKind.dailySummary.rawValue, FetchKind.heartRate.rawValue]
        }
        var stamps = Dictionary(
            try Row.fetchAll(db, sql: sql, arguments: arguments).map { ($0["key"] as String, $0["stamp"] as Int64) },
            uniquingKeysWith: { max($0, $1) })
        guard workouts, kind == .heartRate || kind == .energy else { return stamps }
        // Hidden ones too: hiding one gives its readings back to the day.
        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT w.start_at, w.end_at, w.day, MAX(w.stored_at, IFNULL(c.chosen_at, 0)) AS changed_at
                FROM workout AS w LEFT JOIN workout_choice AS c ON c.session = w.session
                """)
        {
            let changedAt: Int64 = row["changed_at"]
            var days: [String] = []
            if kind == .energy {
                days = [row["day"]]
            } else {
                // A workout ending at midnight doesn't reach the next day.
                let startAt: Int64 = row["start_at"]
                var day = DayKey(Date(unixSeconds: startAt), in: zone)
                let last = DayKey(Date(unixSeconds: max(startAt, (row["end_at"] as Int64) - 1)), in: zone)
                while day <= last {
                    days.append(day.description)
                    day = day.adding(days: 1)
                }
            }
            for day in days where stamps[day] != nil { stamps[day] = max(stamps[day] ?? 0, changedAt) }
        }
        return stamps
    }

    private static func metricKind(_ kind: HealthKind) -> String {
        switch kind {
        case .restingHeartRate: Contributor.restingHeartRate.kind
        case .hrv: NightSDNN.kind
        default: Contributor.breathing.kind
        }
    }

    /// The unit's items for `kinds`, read in one transaction with the clock's time of the read. A heart rate day is midnight
    /// to midnight in the clock's zone; a unit without data any more (a hidden workout) has no items.
    public func healthBatch(_ unit: HealthUnit, kinds: Set<HealthKind>, clock: any VeselClock) async throws -> HealthBatchRead {
        try await writer.read { db in
            let snapshot = clock.now
            let last = try Row.fetchOne(db, sql: "SELECT digest, sync_version FROM health_write WHERE unit = ?", arguments: [unit.id]).map {
                HealthWritten(digest: $0["digest"], syncVersion: $0["sync_version"])
            }
            let items =
                unit.kind == .workout
                ? try Self.workoutItems(db, session: unit.key)
                : try unit.day.map { try Self.healthItems(db, unit.kind, day: $0, zone: clock.timeZone, workouts: kinds.contains(.workout)) } ?? []
            return HealthBatchRead(batch: HealthBatch(unit: unit, items: items, allowed: kinds), snapshot: snapshot, last: last)
        }
    }

    private static func healthItems(_ db: Database, _ kind: HealthKind, day: DayKey, zone: TimeZone, workouts: Bool) throws -> [HealthItem] {
        switch kind {
        case .heartRate:
            let samples = try StressInputs.heartRates(db, day: day, zone: zone)
            return HealthMapping.heartRate(samples, leavingOut: workouts ? try StressInputs.workouts(db, day: day, zone: zone) : [])
        case .steps:
            let text = try String.fetchOne(
                db, sql: "SELECT json_extract(json, '$.samples') FROM raw_export WHERE day = ? AND kind = ?",
                arguments: [day.description, FetchKind.activitySamples.rawValue])
            let samples = text.flatMap { try? StoredJSON.decode([HourlySteps.Sample].self, from: $0) } ?? []
            return HealthMapping.steps(day: day, samples: samples)
        case .sleep:
            return try SleepNightRecord.fetchOne(db, key: day.description).map { HealthMapping.sleep(try $0.model()) } ?? []
        case .energy:
            guard
                let calories = try String.fetchOne(db, sql: "SELECT calories_json FROM activity_day WHERE day = ?", arguments: [day.description])
                    .map({ try StoredJSON.decode(ActivityDay.Calories.self, from: $0) }),
                let summary = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT r.utc_offset_seconds, l.stored_at FROM raw_export AS r
                        JOIN band_ledger AS l ON l.day = r.day AND l.fetch_kind = r.kind WHERE r.day = ? AND r.kind = ?
                        """, arguments: [day.description, FetchKind.dailySummary.rawValue])
            else { return [] }
            let started = workouts ? try Self.workouts(db, from: day, through: day).filter { !$0.isHidden }.map(\.workout) : nil
            return HealthMapping.energy(
                day: day, calories: calories, utcOffsetSeconds: summary["utc_offset_seconds"], readAt: Date(unixSeconds: summary["stored_at"]),
                workouts: started)
        case .workout:
            return []
        case .restingHeartRate, .respiratoryRate, .hrv:
            guard
                let value = try Double.fetchOne(
                    db, sql: "SELECT value FROM computed_metric WHERE kind = ? AND day = ? AND hour IS NULL", arguments: [metricKind(kind), day.description])
            else { return [] }
            let sleep = try SleepNightRecord.fetchOne(db, key: day.description)?.model()
            // The Nightly Recharge is stored under the night or the day after, by its result date.
            let offset =
                try Int.fetchOne(
                    db, sql: "SELECT utc_offset_seconds FROM raw_export WHERE kind = ? AND day IN (?, ?) ORDER BY day LIMIT 1",
                    arguments: [FetchKind.nightlyRecharge.rawValue, day.description, day.adding(days: 1).description]) ?? zone.secondsFromGMT(for: day.start(in: zone))
            switch kind {
            case .restingHeartRate: return [HealthMapping.restingHeartRate(night: day, bpm: value, sleep: sleep, utcOffsetSeconds: offset)]
            case .hrv: return [HealthMapping.hrv(night: day, ms: value, sleep: sleep, utcOffsetSeconds: offset)]
            default: return [HealthMapping.respiratoryRate(night: day, breathsPerMinute: value, sleep: sleep, utcOffsetSeconds: offset)]
            }
        }
    }

    /// A shown workout with its label, its route, its day's BMR and the 24/7 readings during it.
    private static func workoutItems(_ db: Database, session: String) throws -> [HealthItem] {
        guard let stored = try workouts(db, where: "w.session = ?", arguments: [session]).first, !stored.isHidden,
            let labelled = try labelled(db, [stored]).first
        else { return [] }
        let workout = stored.workout
        let bmr =
            try String.fetchOne(db, sql: "SELECT calories_json FROM activity_day WHERE day = ?", arguments: [workout.day.description])
            .map { try StoredJSON.decode(ActivityDay.Calories.self, from: $0).bmr } ?? 0
        let readings = try HeartRateSampleRecord
            .filter(sql: "ts >= ? AND ts <= ?", arguments: [workout.start.unixSeconds, workout.interval.end.unixSeconds])
            .order(sql: "ts")
            .fetchAll(db)
            .map(\.model)
        return HealthMapping.workout(workout, label: labelled.label, route: labelled.route?.points ?? [], bmr: bmr, dayHeartRates: readings)
            .map { [$0] } ?? []
    }

    /// The unit was written as `digest` under `version`, from rows read at `at`.
    public func markHealthWritten(_ unit: HealthUnit, digest: String, version: Int64, at: Date) async throws {
        try await writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO health_write (unit, kind, mapping_version, digest, sync_version, written_at) VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT (unit) DO UPDATE SET kind = excluded.kind, mapping_version = excluded.mapping_version,
                        digest = excluded.digest, sync_version = excluded.sync_version, written_at = excluded.written_at
                    """,
                arguments: [unit.id, unit.kind.rawValue, HealthMapping.version(unit.kind), digest, version, at.unixSeconds])
        }
    }

    /// The unit's copies in Health were removed.
    public func forgetHealthWrite(_ unit: HealthUnit) async throws {
        try await writer.write { try $0.execute(sql: "DELETE FROM health_write WHERE unit = ?", arguments: [unit.id]) }
    }
}
