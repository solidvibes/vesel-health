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
/// `written_at`, or it has a row and no data any more. The writer never runs beside a read, so every `stored_at` it can see
/// is no later than its snapshot, and a later read always stamps the same second or later.
extension AppDatabase {
    /// "on" while Vesel writes to Health. Not uploaded.
    public static let healthWriteKey = "health.write"
    /// JSON `HealthRun`. Not uploaded.
    public static let healthLastRunKey = "health.lastRun"

    /// Turning on forgets every earlier write, so everything is written again (same ids, so nothing doubles); turning off
    /// keeps how the last write went.
    public func setHealthWrite(_ on: Bool) async throws {
        try await writer.write { db in
            if on {
                try db.execute(sql: "DELETE FROM health_write")
                try db.execute(sql: "DELETE FROM setting WHERE key = ?", arguments: [Self.healthLastRunKey])
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

    /// Units of `kinds` to write, newest first.
    public func pendingHealthUnits(kinds: Set<HealthKind>) async throws -> [HealthUnit] {
        try await writer.read { db in
            var pending: [HealthUnit] = []
            for kind in HealthKind.allCases where kinds.contains(kind) {
                let stamps = try Self.healthSources(db, kind)
                let written = Dictionary(
                    uniqueKeysWithValues: try Row.fetchAll(
                        db, sql: "SELECT unit, mapping_version, written_at FROM health_write WHERE kind = ?", arguments: [kind.rawValue]
                    ).map { ($0["unit"] as String, (version: $0["mapping_version"] as Int, writtenAt: $0["written_at"] as Int64)) })
                for (key, stamp) in stamps {
                    let unit = HealthUnit(kind: kind, key: key)
                    guard let row = written[unit.id] else {
                        pending.append(unit)
                        continue
                    }
                    if row.version != HealthMapping.version(kind) || stamp >= row.writtenAt { pending.append(unit) }
                }
                pending += written.keys.compactMap(HealthUnit.init(id:)).filter { stamps[$0.key] == nil }
            }
            return pending.sorted { ($0.key, $1.kind.rawValue) > ($1.key, $0.kind.rawValue) }
        }
    }

    /// Each unit of `kind` that has data, with the latest time one of its sources was stored or worked out.
    private static func healthSources(_ db: Database, _ kind: HealthKind) throws -> [String: Int64] {
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
        case .restingHeartRate, .respiratoryRate:
            sql = """
                SELECT day AS key, MAX(computed_at, \(sleepStamp("metric.day"))) AS stamp
                FROM computed_metric AS metric WHERE kind = ? AND hour IS NULL
                """
            arguments = [metricKind(kind)]
        }
        return Dictionary(
            try Row.fetchAll(db, sql: sql, arguments: arguments).map { ($0["key"] as String, $0["stamp"] as Int64) },
            uniquingKeysWith: { max($0, $1) })
    }

    private static func metricKind(_ kind: HealthKind) -> String {
        kind == .restingHeartRate ? Contributor.restingHeartRate.kind : Contributor.breathing.kind
    }

    /// The unit's items for `kinds`, read in one transaction with the clock's time of the read. A day is midnight to midnight
    /// in the clock's zone; a unit without data any more has no items.
    public func healthBatch(_ unit: HealthUnit, kinds: Set<HealthKind>, clock: any VeselClock) async throws -> HealthBatchRead {
        try await writer.read { db in
            let snapshot = clock.now
            let last = try Row.fetchOne(db, sql: "SELECT digest, sync_version FROM health_write WHERE unit = ?", arguments: [unit.id]).map {
                HealthWritten(digest: $0["digest"], syncVersion: $0["sync_version"])
            }
            let items = try unit.day.map { try Self.healthItems(db, unit.kind, day: $0, zone: clock.timeZone) } ?? []
            return HealthBatchRead(batch: HealthBatch(unit: unit, items: items, allowed: kinds), snapshot: snapshot, last: last)
        }
    }

    private static func healthItems(_ db: Database, _ kind: HealthKind, day: DayKey, zone: TimeZone) throws -> [HealthItem] {
        switch kind {
        case .heartRate:
            let samples = try HeartRateSampleRecord
                .filter(sql: "ts >= ? AND ts < ?", arguments: [day.start(in: zone).unixSeconds, day.adding(days: 1).start(in: zone).unixSeconds])
                .order(sql: "ts")
                .fetchAll(db)
                .map(\.model)
            return HealthMapping.heartRate(samples)
        case .steps:
            let text = try String.fetchOne(
                db, sql: "SELECT json_extract(json, '$.samples') FROM raw_export WHERE day = ? AND kind = ?",
                arguments: [day.description, FetchKind.activitySamples.rawValue])
            let samples = text.flatMap { try? StoredJSON.decode([HourlySteps.Sample].self, from: $0) } ?? []
            return HealthMapping.steps(day: day, samples: samples)
        case .sleep:
            return try SleepNightRecord.fetchOne(db, key: day.description).map { HealthMapping.sleep(try $0.model()) } ?? []
        case .restingHeartRate, .respiratoryRate:
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
            return kind == .restingHeartRate
                ? [HealthMapping.restingHeartRate(night: day, bpm: value, sleep: sleep, utcOffsetSeconds: offset)]
                : [HealthMapping.respiratoryRate(night: day, breathsPerMinute: value, sleep: sleep, utcOffsetSeconds: offset)]
        }
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
