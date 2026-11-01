import Foundation
import GRDB
import VeselCore

/// Works out the numbers for the nights a sync touched, and for the later nights whose 28-night range
/// they feed, and stores them in `computed_metric`. The analysis itself lives in VeselCore; this only
/// gathers its inputs and writes its results.
public struct MetricsUpdater: Sendable {
    /// A night this recent is always recomputed: Polar may still be finishing it.
    static let recentNights = 3

    private let database: AppDatabase
    private let clock: any VeselClock

    public init(database: AppDatabase, clock: any VeselClock) {
        self.database = database
        self.clock = clock
    }

    /// After a sync: the recent nights, nights with data but no numbers yet, and nights stored under an older
    /// method version; then the same for stress days. Returns the nights that were recomputed.
    @discardableResult
    public func updateAfterSync() async throws -> Set<DayKey> {
        let today = clock.today
        let touched = try await database.writer.read { db in try Self.touchedNights(db, today: today) }
        let nights = try await recompute(nights: touched)
        let stress = StressUpdater(clock: clock)
        let days = try await database.writer.read { db in try stress.touchedDays(db, today: today) }
        try await recomputeStress(days: days)
        return nights
    }

    /// Recomputes the stress numbers of `days` and of the later days within 14 days, whose baseline includes them.
    @discardableResult
    public func recomputeStress(days: Set<DayKey>) async throws -> Set<DayKey> {
        let now = clock.now
        let stress = StressUpdater(clock: clock)
        return try await database.writer.write { db in try stress.recompute(db, days: days, now: now) }
    }

    /// Recomputes `nights` and every later night within 28 days that has data, since their range includes these.
    @discardableResult
    public func recompute(nights: Set<DayKey>) async throws -> Set<DayKey> {
        guard !nights.isEmpty else { return [] }
        let now = clock.now
        return try await database.writer.write { db in
            let existing = try Self.nightsWithData(db)
            let affected = existing.filter { night in
                nights.contains(night)
                    || nights.contains { $0 < night && night <= $0.adding(days: PersonalRange.windowNights) }
            }
            guard let first = affected.min(), let last = affected.max() else { return [] }

            let windowStart = first.adding(days: -PersonalRange.windowNights)
            var summaries: [DayKey: SleepSummary] = [:]
            var recharges: [DayKey: NightlyRecharge] = [:]
            var values: [DayKey: ContributorValues] = [:]
            for night in existing where night >= windowStart && night <= last {
                let model = try SleepNightRecord.fetchOne(db, key: night.description)?.model()
                let recharge = try NightlyRechargeRecord.fetchOne(db, key: night.description)?.model()
                let summary = try model.map { SleepSummary($0, heartRates: try Self.heartRates(db, from: $0.start, to: $0.end)) }
                let skin = try summary.map { try Self.skinTemperatures(db, from: $0.start, to: $0.end) } ?? []
                summaries[night] = summary
                recharges[night] = recharge
                values[night] = RecoveryContributors.values(recharge: recharge, summary: summary, skinTemperatures: skin)
            }
            let history = values.mapValues(\.values)

            for night in affected.sorted() {
                var metrics: [ComputedMetric] = []
                if let summary = summaries[night] {
                    metrics += summary.metrics(computedAt: now)
                }
                if let recharge = recharges[night], let status = RecoveryStatus(recharge) {
                    metrics.append(status.metric(computedAt: now))
                }
                if let nightValues = values[night] {
                    metrics += RecoveryContributors.metrics(night: night, values: nightValues, history: history, computedAt: now)
                }
                for metric in metrics { try ComputedMetricRecord(metric).upsert(db) }
                // A number whose input went away (a reading Polar dropped, a status it withdrew) goes too.
                let methods = Self.currentVersions.map(\.method)
                let kinds = metrics.map(\.kind)
                try db.execute(
                    sql: """
                        DELETE FROM computed_metric WHERE day = ? AND hour IS NULL
                        AND method IN (\(databaseQuestionMarks(count: methods.count)))
                        AND kind NOT IN (\(databaseQuestionMarks(count: max(kinds.count, 1))))
                        """,
                    arguments: StatementArguments([night.description] + methods + (kinds.isEmpty ? [""] : kinds))
                )
            }
            return affected
        }
    }

    /// Method versions in force. A night stored under another version is recomputed.
    private static let currentVersions: [(method: String, version: Int)] = [
        (SleepSummary.method, SleepSummary.version),
        (RecoveryStatus.method, RecoveryStatus.version),
        (RecoveryContributors.method, RecoveryContributors.version),
    ]

    private static func touchedNights(_ db: Database, today: DayKey) throws -> Set<DayKey> {
        var touched = Set<DayKey>()
        let recent = today.adding(days: -(recentNights - 1))
        touched.formUnion(try nightsWithData(db).filter { $0 >= recent })

        let missing = try String.fetchAll(
            db,
            sql: """
                SELECT night FROM sleep_night
                WHERE night NOT IN (SELECT day FROM computed_metric WHERE kind = ?)
                UNION
                SELECT night FROM nightly_recharge
                WHERE recovery_indicator IS NOT NULL AND night NOT IN (SELECT day FROM computed_metric WHERE kind = ?)
                """, arguments: [MetricKind.sleepAsleep, MetricKind.recoveryStatus])
        touched.formUnion(missing.compactMap(DayKey.init))

        for (method, version) in currentVersions {
            let stale = try String.fetchAll(
                db, sql: "SELECT DISTINCT day FROM computed_metric WHERE method = ? AND method_version <> ?",
                arguments: [method, version]
            )
            touched.formUnion(stale.compactMap(DayKey.init))
        }
        return touched
    }

    static func nightsWithData(_ db: Database) throws -> Set<DayKey> {
        Set(try String.fetchAll(db, sql: "SELECT night FROM sleep_night UNION SELECT night FROM nightly_recharge").compactMap(DayKey.init))
    }

    private static func heartRates(_ db: Database, from start: Date, to end: Date) throws -> [HeartRateSample] {
        try HeartRateSampleRecord
            .filter(sql: "ts >= ? AND ts <= ?", arguments: [start.unixSeconds, end.unixSeconds])
            .fetchAll(db)
            .map(\.model)
    }

    private static func skinTemperatures(_ db: Database, from start: Date, to end: Date) throws -> [SkinTemperatureSample] {
        try SkinTemperatureSampleRecord
            .filter(sql: "ts >= ? AND ts <= ?", arguments: [start.unixSeconds, end.unixSeconds])
            .fetchAll(db)
            .map { SkinTemperatureSample(time: Date(unixSeconds: $0.ts), celsius: $0.celsius) }
    }
}
