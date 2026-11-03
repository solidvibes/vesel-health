import Foundation
import GRDB
import VeselCore

extension AppDatabase {
    // MARK: Profile and band

    public func save(_ profile: Profile) async throws {
        try await writer.write { try ProfileRecord(profile).upsert($0) }
    }

    public func profile() async throws -> Profile? {
        try await writer.read { try ProfileRecord.fetchOne($0)?.model }
    }

    public func save(_ band: BandInfo) async throws {
        try await writer.write { try BandRecord(band).upsert($0) }
    }

    public func band() async throws -> BandInfo? {
        try await writer.read { try BandRecord.fetchOne($0)?.model }
    }

    /// What the band said about sleep at the last sync (`SleepRecordingStatus`), kept for the next launch. Not health data; never uploaded.
    public static let sleepStatusKey = "band.sleepStatus"

    /// Forgets the band after its factory reset: everything still on it is gone, so its ledger rows count as cleared,
    /// what it last said about sleep no longer holds, and the next Loop gets workout detection switched on. History stays.
    public func forgetBand(at date: Date) async throws {
        try await writer.write { db in
            _ = try BandRecord.deleteAll(db)
            try db.execute(
                sql: "DELETE FROM setting WHERE key IN (?, ?, ?)",
                arguments: [Self.sleepStatusKey, Self.workoutDetectionSetUpKey, Self.workoutDetectionKey]
            )
            try db.execute(sql: "UPDATE band_ledger SET deleted_from_band_at = ? WHERE deleted_from_band_at IS NULL", arguments: [date.unixSeconds])
        }
    }

    // MARK: Band data

    /// Stores fetched payloads, any kinds and days, in one transaction: each payload as it came off the band,
    /// its typed rows, and a ledger row, also when the day was empty. A day already stored with data is never
    /// replaced by an empty re-fetch (the band returns nothing for days it has cleared). An empty day read empty
    /// again keeps the earlier read's time, so clearing can tell one empty read from two.
    public func save(_ payloads: [BandPayload], fetchedAt: Date) async throws {
        let contents = try payloads.map { ($0, try $0.content()) }
        try await writer.write { db in
            for (payload, content) in contents {
                if payload.isEmpty, try Self.storedSampleCount(db, payload) > 0 { continue }
                try RawExportRecord(payload, fetchedAt: fetchedAt).upsert(db)
                try db.execute(
                    sql: """
                        INSERT INTO band_ledger (day, fetch_kind, stored_at, sample_count) VALUES (?, ?, ?, ?)
                        ON CONFLICT (day, fetch_kind) DO UPDATE SET
                            earlier_empty_at = CASE WHEN excluded.sample_count = 0 AND sample_count = 0 THEN stored_at END,
                            stored_at = excluded.stored_at,
                            sample_count = excluded.sample_count
                        """,
                    arguments: [payload.day.description, payload.kind.rawValue, fetchedAt.unixSeconds, payload.sampleCount]
                )
                try Self.save(content, rawJSON: payload.json, db)
            }
        }
    }

    /// Only the typed rows of payloads with data: no raw export, no ledger row. The readings show at once, but clearing
    /// doesn't count them until `save(_:fetchedAt:)` stores the day.
    public func saveReadings(_ payloads: [BandPayload]) async throws {
        let contents = try payloads.filter { !$0.isEmpty }.map { ($0.json, try $0.content()) }
        try await writer.write { db in
            for (json, content) in contents {
                try Self.save(content, rawJSON: json, db)
            }
        }
    }

    private static func storedSampleCount(_ db: Database, _ payload: BandPayload) throws -> Int {
        try Int.fetchOne(
            db,
            sql: "SELECT sample_count FROM band_ledger WHERE day = ? AND fetch_kind = ?",
            arguments: [payload.day.description, payload.kind.rawValue]
        ) ?? 0
    }

    private static func save(_ content: BandPayloadContent, rawJSON: String, _ db: Database) throws {
        switch content {
        case .sleep(let night): try SleepNightRecord(night, rawJSON: rawJSON).upsert(db)
        case .nightlyRecharge(let recharge): try NightlyRechargeRecord(recharge, rawJSON: rawJSON).upsert(db)
        case .heartRates(let samples): try save(heartRates: samples, db)
        case .ppi(let sessions): try sessions.forEach { try save($0, db) }
        case .skinTemperatures(let samples): try save(skinTemperatures: samples, db)
        case .activity(let activity): try ActivityDayRecord(activity).upsert(db)
        case .none: break
        }
    }

    /// The latest day of `kind` in the ledger.
    public func lastStoredDay(_ kind: FetchKind) async throws -> DayKey? {
        try await writer.read { db in
            try String.fetchOne(db, sql: "SELECT MAX(day) FROM band_ledger WHERE fetch_kind = ?", arguments: [kind.rawValue])
                .flatMap(DayKey.init)
        }
    }

    public func ledger(_ kinds: [FetchKind]) async throws -> [LedgerEntry] {
        try await writer.read { db in
            try BandLedgerRecord
                .filter(kinds.map(\.rawValue).contains(Column("fetch_kind")))
                .order(sql: "day, fetch_kind")
                .fetchAll(db)
                .compactMap(\.model)
        }
    }

    public func markDeletedFromBand(_ kind: FetchKind, through day: DayKey, at date: Date) async throws {
        try await writer.write { db in
            try db.execute(
                sql: """
                    UPDATE band_ledger SET deleted_from_band_at = ?
                    WHERE fetch_kind = ? AND day <= ? AND deleted_from_band_at IS NULL
                    """,
                arguments: [date.unixSeconds, kind.rawValue, day.description]
            )
        }
    }

    public func save(_ night: SleepNight, rawJSON: String) async throws {
        try await writer.write { try SleepNightRecord(night, rawJSON: rawJSON).upsert($0) }
    }

    public func sleepNight(_ night: DayKey) async throws -> SleepNight? {
        try await writer.read { try SleepNightRecord.fetchOne($0, key: night.description)?.model() }
    }

    public func save(_ recharge: NightlyRecharge, rawJSON: String) async throws {
        try await writer.write { try NightlyRechargeRecord(recharge, rawJSON: rawJSON).upsert($0) }
    }

    /// Whether sleep or a Nightly Recharge is stored for `night`, the nights `shownNight` shows.
    public func hasNight(_ night: DayKey) async throws -> Bool {
        try await writer.read { db in
            try Bool.fetchOne(
                db,
                sql: """
                    SELECT EXISTS (SELECT 1 FROM sleep_night WHERE night = ?) OR EXISTS (SELECT 1 FROM nightly_recharge WHERE night = ?)
                    """, arguments: [night.description, night.description]) ?? false
        }
    }

    public func nightlyRecharge(_ night: DayKey) async throws -> NightlyRecharge? {
        try await writer.read { try NightlyRechargeRecord.fetchOne($0, key: night.description)?.model() }
    }

    public func save(heartRates: [HeartRateSample]) async throws {
        try await writer.write { try Self.save(heartRates: heartRates, $0) }
    }

    private static func save(heartRates: [HeartRateSample], _ db: Database) throws {
        for sample in heartRates {
            try HeartRateSampleRecord(sample).upsert(db)
        }
    }

    public func heartRates(from start: Date, to end: Date) async throws -> [HeartRateSample] {
        try await writer.read { db in
            try HeartRateSampleRecord
                .filter(sql: "ts >= ? AND ts < ?", arguments: [start.unixSeconds, end.unixSeconds])
                .order(sql: "ts")
                .fetchAll(db)
                .map(\.model)
        }
    }

    public func save(_ session: PPISession) async throws {
        try await writer.write { try Self.save(session, $0) }
    }

    private static func save(_ session: PPISession, _ db: Database) throws {
        let record = PPISessionRecord(session)
        try record.upsert(db)
        let sessionId = try Int64.fetchOne(db, sql: "SELECT id FROM ppi_session WHERE start_ts = ?", arguments: [record.startTs])!
        for sample in session.samples {
            try PPISampleRecord(sample, sessionId: sessionId).upsert(db)
        }
    }

    public func save(skinTemperatures: [SkinTemperatureSample]) async throws {
        try await writer.write { try Self.save(skinTemperatures: skinTemperatures, $0) }
    }

    private static func save(skinTemperatures: [SkinTemperatureSample], _ db: Database) throws {
        for sample in skinTemperatures {
            try SkinTemperatureSampleRecord(sample).upsert(db)
        }
    }

    public func save(_ activity: ActivityDay) async throws {
        try await writer.write { try ActivityDayRecord(activity).upsert($0) }
    }

    // MARK: Sync runs

    public func startSyncRun(_ trigger: SyncTrigger, at date: Date) async throws -> Int64 {
        try await writer.write { db in
            var record = SyncRunRecord(trigger: trigger.rawValue, startedAt: date.unixSeconds)
            try record.insert(db)
            return record.id!
        }
    }

    public func finishSyncRun(_ id: Int64, outcome: SyncOutcome, detail: String?, at date: Date) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE sync_run SET finished_at = ?, outcome = ?, detail = ? WHERE id = ?",
                arguments: [date.unixSeconds, outcome.rawValue, detail, id]
            )
        }
    }

    public func latestSyncRun() async throws -> SyncRun? {
        try await writer.read { try SyncRunRecord.order(sql: "started_at DESC, id DESC").fetchOne($0)?.model }
    }

    /// The `limit` newest sync runs, newest first.
    public func latestSyncRuns(limit: Int) async throws -> [SyncRun] {
        try await writer.read { try SyncRunRecord.order(sql: "started_at DESC, id DESC").limit(limit).fetchAll($0).map(\.model) }
    }

    /// When the band was last read all the way through.
    public func lastSuccessfulSync() async throws -> Date? {
        try await writer.read { try Self.lastSuccessfulSync($0) }
    }

    static func lastSuccessfulSync(_ db: Database) throws -> Date? {
        try Int64.fetchOne(db, sql: "SELECT MAX(finished_at) FROM sync_run WHERE outcome = ?", arguments: [SyncOutcome.success.rawValue])
            .map(Date.init(unixSeconds:))
    }

    // MARK: Link to the Loop

    /// Stores one change in the link to the Loop and deletes those older than `BandLink.keptFor`.
    public func save(_ link: BandLink) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "INSERT INTO band_link (at, event, reason) VALUES (?, ?, ?)",
                arguments: [link.at.unixSeconds, link.event.rawValue, link.reason]
            )
            try db.execute(sql: "DELETE FROM band_link WHERE at < ?", arguments: [link.at.addingTimeInterval(-BandLink.keptFor).unixSeconds])
        }
    }

    /// Changes in the link from `start` on, oldest first.
    public func bandLinks(since start: Date) async throws -> [BandLink] {
        try await writer.read { db in
            try Row.fetchAll(db, sql: "SELECT at, event, reason FROM band_link WHERE at >= ? ORDER BY at, id", arguments: [start.unixSeconds])
                .compactMap { row in
                    BandLink.Event(rawValue: row["event"]).map { BandLink(at: Date(unixSeconds: row["at"]), event: $0, reason: row["reason"]) }
                }
        }
    }

    // MARK: Computed metrics

    public func save(_ metric: ComputedMetric) async throws {
        try await writer.write { try ComputedMetricRecord(metric).upsert($0) }
    }

    public func computedMetric(_ kind: String, day: DayKey, hour: Int? = nil) async throws -> ComputedMetric? {
        try await writer.read { db in
            try ComputedMetricRecord
                .filter(sql: "kind = ? AND day = ? AND hour IS ?", arguments: [kind, day.description, hour])
                .fetchOne(db)?
                .model()
        }
    }

    // MARK: Alerts

    /// Records an alert, or updates today's pending one (due at 07:00) to what it says now.
    public func save(_ event: AlertEvent) async throws {
        try await writer.write { try AlertEventRecord(event).upsert($0) }
    }

    /// Drops a pending alert that no longer holds: it never went out.
    public func deleteAlertEvent(_ kind: AlertKind, day: DayKey) async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM alert_event WHERE kind = ? AND day = ?", arguments: [kind.rawValue, day.description])
        }
    }

    public func alertEvents(day: DayKey) async throws -> [AlertEvent] {
        try await writer.read { db in try Self.alertEvents(db, day: day) }
    }

    static func alertEvents(_ db: Database, day: DayKey) throws -> [AlertEvent] {
        try AlertEventRecord
            .filter(sql: "day = ?", arguments: [day.description])
            .order(sql: "fired_at DESC")
            .fetchAll(db)
            .compactMap { try $0.model() }
    }

    public func alertSettings() async throws -> AlertSettings {
        try await writer.read { db in try Self.alertSettings(db) }
    }

    public func setAlert(_ kind: AlertKind, on: Bool) async throws {
        try await writer.write { try SettingRecord(key: Self.settingKey(kind), value: on ? "on" : "off").upsert($0) }
    }

    private static func settingKey(_ kind: AlertKind) -> String { "alerts.\(kind.rawValue)" }

    static func alertSettings(_ db: Database) throws -> AlertSettings {
        var values: [AlertKind: Bool] = [:]
        for kind in AlertKind.allCases {
            if let value = try String.fetchOne(db, sql: "SELECT value FROM setting WHERE key = ?", arguments: [settingKey(kind)]) {
                values[kind] = value == "on"
            }
        }
        return AlertSettings(values)
    }

    /// What the alerts are decided from for `today`.
    public func alertFacts(today: DayKey, timeZone: TimeZone) async throws -> AlertFacts {
        try await writer.read { db in
            let first = today.adding(days: -PersonalRange.windowNights)
            let kinds = [MetricKind.recoveryStatus, Contributor.hrv.kind, Contributor.restingHeartRate.kind, MetricKind.sleepAsleep]
            let metrics =
                try ComputedMetricRecord
                .filter(
                    sql: "day >= ? AND day <= ? AND hour IS NULL AND kind IN (?, ?, ?, ?)",
                    arguments: StatementArguments([first.description, today.description] + kinds)
                )
                .fetchAll(db)
                .map { try $0.model() }
            var nights: [DayKey: AlertNight] = [:]
            for metric in metrics {
                var night = nights[metric.day] ?? AlertNight()
                switch metric.kind {
                case MetricKind.recoveryStatus: night.status = RecoveryStatus(metric)
                case Contributor.hrv.kind: night.hrv = ContributorReading(metric)
                case Contributor.restingHeartRate.kind: night.restingHeartRate = ContributorReading(metric)
                case MetricKind.sleepAsleep: night.asleepMinutes = metric.value
                default: break
                }
                nights[metric.day] = night
            }
            let earlier = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM (SELECT night FROM sleep_night UNION SELECT night FROM nightly_recharge)
                    WHERE night < ? AND night >= ?
                    """, arguments: [today.description, first.description])!
            let span =
                try ComputedMetricRecord
                .filter(sql: "kind = ? AND day = ? AND hour IS NULL", arguments: [MetricKind.stressBusiestSpan, today.description])
                .fetchOne(db)
                .flatMap { try $0.model() }
                .flatMap(StressSpan.init)
            var lastBefore: [AlertKind: DayKey] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT kind, MAX(day) AS day FROM alert_event WHERE day < ? GROUP BY kind", arguments: [today.description]) {
                if let kind = AlertKind(rawValue: row["kind"]), let day = DayKey(row["day"] as String) { lastBefore[kind] = day }
            }
            var firedToday: [AlertKind: Date] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT kind, fired_at FROM alert_event WHERE day = ?", arguments: [today.description]) {
                if let kind = AlertKind(rawValue: row["kind"]) { firedToday[kind] = Date(unixSeconds: row["fired_at"]) }
            }
            return AlertFacts(
                today: today, timeZone: timeZone, nights: nights, earlierNights: earlier,
                stressDays: try Self.stressBaselineDays(db, before: today), stressSpan: span,
                lastBefore: lastBefore, firedToday: firedToday, settings: try Self.alertSettings(db)
            )
        }
    }

    // MARK: Settings

    public func setting(_ key: String) async throws -> String? {
        try await writer.read { try String.fetchOne($0, sql: "SELECT value FROM setting WHERE key = ?", arguments: [key]) }
    }

    /// Sets each key to its value, or removes it when the value is nil, in one transaction.
    public func setSettings(_ values: [String: String?]) async throws {
        try await writer.write { db in
            for (key, value) in values {
                if let value {
                    try SettingRecord(key: key, value: value).upsert(db)
                } else {
                    try db.execute(sql: "DELETE FROM setting WHERE key = ?", arguments: [key])
                }
            }
        }
    }

    /// How the screens write weight, height, waist and skin temperature. Not health data; never sent to the Loop or uploaded.
    public func setUnits(_ units: Units) async throws {
        try await setSettings([Self.unitsKey: units.rawValue])
    }

    static let unitsKey = "units"

    /// Metric unless the owner chose otherwise.
    static func units(_ db: Database) throws -> Units {
        try String.fetchOne(db, sql: "SELECT value FROM setting WHERE key = ?", arguments: [unitsKey]).flatMap(Units.init(rawValue:)) ?? .metric
    }

    // MARK: Mac mini backup

    /// Up to `limit` rows of `table` not yet backed up, after the row `after` (the last one of the previous page).
    /// Alerts still due at 07:00 wait until they have gone out: they may still be dropped.
    public func pendingUploads(_ table: UploadTable, after: Int64 = 0, limit: Int, now: Date) async throws -> [PendingUpload] {
        try await writer.read { db in
            try Self.uploadRows(db, table, filter: "\(table.alias).rowid > ? ORDER BY \(table.alias).rowid LIMIT ?", arguments: [after, limit], now: now)
        }
    }

    /// Marks uploaded exactly the rows the Mac mini acknowledged that still read as they were sent; a row changed
    /// since keeps `uploaded_at = NULL` and goes again next time.
    public func markUploaded(_ table: UploadTable, _ rows: [PendingUpload], at date: Date) async throws {
        guard !rows.isEmpty else { return }
        try await writer.write { db in
            let current = try Self.uploadRows(
                db, table,
                filter: "\(table.alias).rowid IN (\(databaseQuestionMarks(count: rows.count)))",
                arguments: StatementArguments(rows.map(\.rowID)),
                now: date
            )
            let unchanged = Set(current).intersection(rows).map(\.rowID)
            guard !unchanged.isEmpty else { return }
            try db.execute(
                sql: "UPDATE \(table.rawValue) SET uploaded_at = ? WHERE rowid IN (\(databaseQuestionMarks(count: unchanged.count)))",
                arguments: StatementArguments([date.unixSeconds] + unchanged)
            )
        }
    }

    /// Queues every row again, for a Mac mini that may not have them (a new certificate means a new set-up).
    public func clearUploadMarks() async throws {
        try await writer.write { db in
            for table in UploadTable.allCases {
                try db.execute(sql: "UPDATE \(table.rawValue) SET uploaded_at = NULL WHERE uploaded_at IS NOT NULL")
            }
        }
    }

    /// Rows waiting for the Mac mini, across every backed-up table.
    public func pendingUploadCount(now: Date) async throws -> Int {
        try await writer.read { db in
            try UploadTable.allCases.reduce(0) { total, table in
                total
                    + (try Int.fetchOne(
                        db,
                        sql: "SELECT COUNT(*) FROM \(table.rawValue) AS \(table.alias) WHERE \(table.alias).uploaded_at IS NULL\(table.extraFilter)",
                        arguments: table.extraArguments(now: now)
                    ) ?? 0)
            }
        }
    }

    private static func uploadRows(_ db: Database, _ table: UploadTable, filter: String, arguments: StatementArguments, now: Date) throws -> [PendingUpload] {
        let sql = "\(table.select) WHERE \(table.alias).uploaded_at IS NULL\(table.extraFilter) AND \(filter)"
        return try Row.fetchAll(db, sql: sql, arguments: table.extraArguments(now: now) + arguments).map { row in
            var data: [String: UploadValue] = [:]
            for (column, value) in row where !table.hiddenColumns.contains(column) {
                data[column] = UploadValue(value)
            }
            return PendingUpload(rowID: row["_rowid"], key: table.key(row), data: data)
        }
    }
}

/// The phone tables the Mac mini keeps a copy of. The band, its ledger, sync runs and settings stay on the phone.
public enum UploadTable: String, CaseIterable, Sendable {
    case profile
    case sleepNight = "sleep_night"
    case nightlyRecharge = "nightly_recharge"
    case hrSample = "hr_sample"
    case ppiSession = "ppi_session"
    case ppiSample = "ppi_sample"
    case skinTempSample = "skin_temp_sample"
    case activityDay = "activity_day"
    case rawExport = "raw_export"
    case computedMetric = "computed_metric"
    case alertEvent = "alert_event"
    case workout
    case workoutFile = "workout_file"
    case workoutChoice = "workout_choice"
    case workoutRoute = "workout_route"

    fileprivate var alias: String { "t" }

    /// `ppi_session.id` and `alert_event.id` are local row ids; a beat names its session by its start instead.
    fileprivate var select: String {
        switch self {
        case .ppiSample:
            "SELECT t.rowid AS _rowid, t.*, s.start_ts AS session_start_ts FROM ppi_sample AS t JOIN ppi_session AS s ON s.id = t.session_id"
        default:
            "SELECT t.rowid AS _rowid, t.* FROM \(rawValue) AS t"
        }
    }

    fileprivate var hiddenColumns: Set<String> {
        switch self {
        case .ppiSession, .alertEvent: ["_rowid", "uploaded_at", "id"]
        case .ppiSample: ["_rowid", "uploaded_at", "session_id"]
        default: ["_rowid", "uploaded_at"]
        }
    }

    fileprivate var extraFilter: String {
        self == .alertEvent ? " AND t.fired_at <= ?" : ""
    }

    fileprivate func extraArguments(now: Date) -> StatementArguments {
        self == .alertEvent ? [now.unixSeconds] : []
    }

    /// The row's natural key, the same on every upload.
    fileprivate func key(_ row: Row) -> String {
        func text(_ column: String) -> String {
            switch (row[column] as DatabaseValue).storage {
            case .int64(let int): String(int)
            case .string(let string): string
            default: ""
            }
        }
        switch self {
        case .profile: return text("id")
        case .sleepNight, .nightlyRecharge: return text("night")
        case .hrSample, .skinTempSample: return text("ts")
        case .ppiSession: return text("start_ts")
        case .ppiSample: return text("ts_ms")
        case .activityDay: return text("day")
        case .rawExport: return "\(text("day"))/\(text("kind"))"
        case .computedMetric:
            let hour: Int? = row["hour"]
            return [text("kind"), text("day"), hour.map(String.init)].compactMap { $0 }.joined(separator: "/")
        case .alertEvent: return "\(text("kind"))/\(text("day"))"
        case .workout, .workoutChoice: return text("session")
        case .workoutFile: return "\(text("session"))/\(text("name"))"
        case .workoutRoute: return text("started_at")
        }
    }
}

/// One row on its way to the Mac mini: its natural key and its columns.
public struct PendingUpload: Sendable, Hashable {
    /// The row's place in its table on this phone, for paging; never sent.
    public let rowID: Int64
    public let key: String
    public let data: [String: UploadValue]
}

/// A column value as JSON.
public enum UploadValue: Sendable, Hashable, Encodable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)

    init(_ value: DatabaseValue) {
        switch value.storage {
        case .null: self = .null
        case .int64(let int): self = .integer(int)
        case .double(let double): self = .real(double)
        case .string(let string): self = .text(string)
        case .blob(let data): self = .text(data.base64EncodedString())
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .integer(let int): try container.encode(int)
        case .real(let double): try container.encode(double)
        case .text(let string): try container.encode(string)
        }
    }
}
