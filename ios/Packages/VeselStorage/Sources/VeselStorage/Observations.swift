import Foundation
import GRDB
import VeselCore

/// Everything the screens show about one night, read from the database.
public struct NightReport: Sendable, Equatable {
    public var night: DayKey
    public var sleep: SleepNight?
    public var recharge: NightlyRecharge?
    public var metrics: [String: ComputedMetric]

    public func value(_ kind: String) -> Double? { metrics[kind]?.value }

    public var status: RecoveryStatus? { metrics[MetricKind.recoveryStatus].flatMap(RecoveryStatus.init) }

    public var contributors: [ContributorReading] {
        Contributor.allCases.compactMap { metrics[$0.kind].flatMap(ContributorReading.init) }
    }

    public func stageMinutes(_ state: SleepState) -> Double? { value(MetricKind.sleepStage(state)) }
}

public struct TodaySnapshot: Sendable, Equatable {
    /// The newest night up to today.
    public var latest: NightReport?
    /// Recovery and sleep of `latest`, calm of today.
    public var lines: DayLines
    /// Nights with data in the 28 days before `latest`.
    public var earlierNights: Int
    /// The shown day's steps from the daily summary; nil with none (0 counts as none: the Loop wasn't worn).
    public var steps: Int?
    /// When the band was last read for today's steps; nil for a past day and with no steps.
    public var stepsReadAt: Date?
    public var latestHeartRate: HeartRateSample?
    /// The latest stress reading stored up to today; whether it still counts as "now" is for the screen to say.
    public var stressNow: StressNow?
    /// Earlier days with enough readings; stress shows a level from 7.
    public var stressDays: Int
    /// Today's "something's off" alerts, newest first, including one still waiting for 07:00; the screen decides
    /// which have gone out.
    public var alerts: [AlertEvent]
    /// Today only, while any line is still learning its normal.
    public var firstWeek: FirstWeek?
    /// The morning sleep report switch, so Today says how last night will arrive.
    public var morningReportOn: Bool
    /// Today only: the noun of yesterday's workout low recovery names (`Headline.namedWorkout`); nil with none.
    public var yesterdayWorkout: String?
}

/// Everything the Calm page shows about one day.
public struct StressReport: Sendable, Equatable {
    public var day: DayKey
    /// Clean readings, with how the day's beats were cleaned and what the baseline was.
    public var readings: ComputedMetric?
    /// The day's hourly levels, by hour.
    public var hourly: [ComputedMetric]
    /// Daytime hours with beats but no reading, and why.
    public var emptyHours: [StressEmptyHour]
    public var highMinutes: ComputedMetric?
    public var now: StressNow?
    /// Earlier days with enough readings; stress shows a level from 7.
    public var baselineDays: Int

    public var isLearning: Bool { baselineDays < StressThresholds.minimumDays }
}

/// The band sync log as the Syncing page needs it.
public struct SyncLog: Sendable, Equatable {
    /// The newest runs first.
    public var runs: [SyncRun]
    /// When the band was last read all the way through; nil if never.
    public var lastRead: Date?
    /// Finished runs since `lastRead` (all finished runs when never read). A run without `finished_at` is not a try.
    public var triesSinceLastRead: Int

    public init(runs: [SyncRun], lastRead: Date?, triesSinceLastRead: Int) {
        self.runs = runs
        self.lastRead = lastRead
        self.triesSinceLastRead = triesSinceLastRead
    }
}

/// What Body shows: each trended number asked for, for the 90 days it can show and the 28 nights before the first, which the
/// moving normal of the first nights needs; oldest first. Steps (`MetricKind.steps`) come from `activity_day`, one per day with steps.
public struct TrendsSnapshot: Sendable, Equatable {
    public var series: [String: [ComputedMetric]]

    public static let days = 90 + PersonalRange.windowNights

    public static let kinds = [
        MetricKind.recoveryStatus, Contributor.hrv.kind, Contributor.restingHeartRate.kind,
        MetricKind.sleepLowestHeartRate, Contributor.breathing.kind, Contributor.sleep.kind, Contributor.skinTemperature.kind,
        MetricKind.stressHighMinutes, MetricKind.steps,
    ]
}

extension AppDatabase {
    /// What Today shows for `day`. `day` is `today` for the live Today; a past day holds that day's own night, alerts
    /// and calm line and its own steps, and no heart rate or stress reading from now.
    public func observeToday(day: DayKey, today: DayKey) -> some AsyncSequence<TodaySnapshot, any Error> {
        ValueObservation.tracking { db in try Self.todaySnapshot(db, day: day, today: today) }.removeDuplicates().values(in: writer)
    }

    /// The night Today and Night show for `day`; nil when there is none.
    public func observeShownNight(day: DayKey, today: DayKey) -> some AsyncSequence<DayKey?, any Error> {
        ValueObservation.tracking { db in try Self.shownNight(db, day: day, today: today) }.values(in: writer)
    }

    /// The paired band as of its last read; nil before pairing.
    public func observeBand() -> some AsyncSequence<BandInfo?, any Error> {
        ValueObservation.tracking { db in try BandRecord.fetchOne(db)?.model }.removeDuplicates().values(in: writer)
    }

    public func observeUnits() -> some AsyncSequence<Units, any Error> {
        ValueObservation.tracking { db in try Self.units(db) }.removeDuplicates().values(in: writer)
    }

    /// The earliest day with a night, a Nightly Recharge or a heart rate, in `zone`; nil with none.
    public func observeFirstDay(zone: TimeZone) -> some AsyncSequence<DayKey?, any Error> {
        ValueObservation.tracking { db in try Self.firstDay(db, zone: zone) }.values(in: writer)
    }

    /// The lines of every day from `first` through `last`.
    public func observeDayLines(from first: DayKey, through last: DayKey) -> some AsyncSequence<[DayKey: DayLines], any Error> {
        ValueObservation.tracking { db in try Self.dayLines(db, from: first, through: last) }.values(in: writer)
    }

    /// The usual bedtime from the sleep starts of the 28 nights before `night`, in `zone`; nil with fewer than 7.
    /// Reads only `start_at`.
    public func observeUsualBedtime(before night: DayKey, zone: TimeZone) -> some AsyncSequence<UsualBedtime?, any Error> {
        ValueObservation.tracking { db in
            let starts = try Int64.fetchAll(
                db, sql: "SELECT start_at FROM sleep_night WHERE night < ? AND night >= ?",
                arguments: [
                    night.description, night.adding(days: -PersonalRange.windowNights).description,
                ])
            return UsualBedtime.make(starts: starts.map { Date(unixSeconds: $0) }, zone: zone)
        }.values(in: writer)
    }

    /// The day's busiest 2 hours of high stress, read back from `stress.busiestSpan`; nil with none.
    public func observeBusiestSpan(day: DayKey) -> some AsyncSequence<StressSpan?, any Error> {
        ValueObservation.tracking { db in
            try ComputedMetricRecord
                .filter(sql: "kind = ? AND day = ? AND hour IS NULL", arguments: [MetricKind.stressBusiestSpan, day.description])
                .fetchOne(db)
                .flatMap { try $0.model() }
                .flatMap(StressSpan.init)
        }.values(in: writer)
    }

    public func observeNight(_ night: DayKey) -> some AsyncSequence<NightReport?, any Error> {
        ValueObservation.tracking { db in try Self.nightReport(db, night) }.values(in: writer)
    }

    /// The 24/7 heart-rate samples from the start to the end of a night's sleep, both ends included, oldest first.
    /// Empty when the night isn't stored; follows the night when Polar moves its end.
    public func observeNightHeartRates(_ night: DayKey) -> some AsyncSequence<[HeartRateSample], any Error> {
        ValueObservation.tracking { db in
            guard let sleep = try SleepNightRecord.fetchOne(db, key: night.description)?.model() else { return [] }
            return
                try HeartRateSampleRecord
                .filter(sql: "ts >= ? AND ts <= ?", arguments: [sleep.start.unixSeconds, sleep.end.unixSeconds])
                .order(sql: "ts")
                .fetchAll(db)
                .map(\.model)
        }.values(in: writer)
    }

    /// The stretches of `day` (in `zone`) spent asleep, oldest first: the nights stored as `day` and `day + 1` (the evening sleep before
    /// midnight belongs to the next night), each clipped to the day. Reads only `night`, `start_at` and `end_at`.
    public func observeSleepSpans(day: DayKey, zone: TimeZone) -> some AsyncSequence<[ClosedRange<Date>], any Error> {
        let dayStart = day.start(in: zone)
        let dayEnd = day.adding(days: 1).start(in: zone)
        return ValueObservation.tracking { db in
            try Row.fetchAll(
                db, sql: "SELECT night, start_at, end_at FROM sleep_night WHERE night IN (?, ?) ORDER BY start_at",
                arguments: [day.description, day.adding(days: 1).description]
            )
            .compactMap { row -> ClosedRange<Date>? in
                let start = max(Date(timeIntervalSince1970: Double(row["start_at"] as Int64)), dayStart)
                let end = min(Date(timeIntervalSince1970: Double(row["end_at"] as Int64)), dayEnd)
                return start < end ? start...end : nil
            }
        }.values(in: writer)
    }

    /// The `limit` newest sync runs, the last successful read and the finished tries since it. Reads `sync_run` only.
    public func observeSyncRuns(limit: Int) -> some AsyncSequence<SyncLog, any Error> {
        ValueObservation.tracking { db in
            let runs = try SyncRunRecord.order(sql: "started_at DESC, id DESC").limit(limit).fetchAll(db).map(\.model)
            let lastRead = try Self.lastSuccessfulSync(db)
            let tries =
                try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM sync_run WHERE finished_at IS NOT NULL AND finished_at > ?",
                    arguments: [lastRead?.unixSeconds ?? -1]
                ) ?? 0
            return SyncLog(runs: runs, lastRead: lastRead, triesSinceLastRead: tries)
        }.values(in: writer)
    }

    public func observeStress(day: DayKey) -> some AsyncSequence<StressReport, any Error> {
        ValueObservation.tracking { db in try Self.stressReport(db, day: day) }.values(in: writer)
    }

    /// The `kinds` asked for (Body's list by default), for the `TrendsSnapshot.days` days ending on `today`.
    public func observeTrends(endingOn today: DayKey, kinds: [String] = TrendsSnapshot.kinds) -> some AsyncSequence<TrendsSnapshot, any Error> {
        ValueObservation.tracking { db in try Self.trends(db, today: today, kinds: kinds) }.values(in: writer)
    }

    /// The deep, light and REM minutes of each of the `days` nights ending on `night`, oldest first; nights without stages are left out.
    /// Reads only the stage metrics' `day`, `kind` and `value`.
    public func observeSleepStages(endingOn night: DayKey, days: Int) -> some AsyncSequence<[NightStages], any Error> {
        ValueObservation.tracking { db in try Self.sleepStages(db, endingOn: night, days: days) }.values(in: writer)
    }

    /// When each of the `days` nights ending on `night` began and ended, oldest first. Reads only `night`, `start_at` and `end_at`, never
    /// `uploaded_at` or the JSON columns.
    public func observeSleepTimes(endingOn night: DayKey, days: Int) -> some AsyncSequence<[SleepNightTimes], any Error> {
        ValueObservation.tracking { db in
            try Row.fetchAll(
                db, sql: "SELECT night, start_at, end_at FROM sleep_night WHERE night >= ? AND night <= ? ORDER BY night",
                arguments: [night.adding(days: -(days - 1)).description, night.description]
            )
            .compactMap { row -> SleepNightTimes? in
                DayKey(row["night"] as String).map {
                    SleepNightTimes(
                        night: $0, start: Date(unixSeconds: row["start_at"] as Int64), end: Date(unixSeconds: row["end_at"] as Int64))
                }
            }
        }.values(in: writer)
    }

    /// The 5-minute average heart rates of the `days` days ending on `day` in `zone`, oldest first; periods without samples are left out.
    /// Reads only `ts` and `bpm`, so marking rows uploaded doesn't run it again.
    public func observeHeartRatePeriods(endingOn day: DayKey, days: Int, zone: TimeZone) -> some AsyncSequence<[FiveMinuteMean], any Error> {
        let start = day.adding(days: -(days - 1)).start(in: zone)
        let end = day.adding(days: 1).start(in: zone)
        return ValueObservation.tracking { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT ts / 300 AS period, AVG(bpm) AS mean FROM hr_sample WHERE ts >= ? AND ts < ? GROUP BY period ORDER BY period
                    """, arguments: [start.unixSeconds, end.unixSeconds]
            )
            .map { FiveMinuteMean(period: $0["period"], mean: $0["mean"]) }
        }.values(in: writer)
    }

    /// What heart fitness needs for the month before `today`'s: the profile, that month's resting heart rate nights and its days'
    /// seconds per activity class (from the daily summary kept as it came in). Nil without a profile. Read-only; never reads `uploaded_at`.
    public func observeFitnessInputs(today: DayKey) -> some AsyncSequence<FitnessInputs?, any Error> {
        let window = FitnessAge.window(today: today)
        return ValueObservation.tracking { db in
            guard
                let profile = try ProfileRecord
                    .select(
                        Column("id"), Column("birth_year"), Column("sex"), Column("height_cm"), Column("weight_kg"), Column("sleep_goal_minutes"),
                        Column("waist_cm"), Column("measured_vo2max")
                    )
                    .fetchOne(db)?.model
            else { return nil }
            let nights = try Double.fetchAll(
                db,
                sql: """
                    SELECT value FROM computed_metric WHERE kind = ? AND day >= ? AND day <= ? AND hour IS NULL
                    """, arguments: [FitnessAge.restingHeartRateKind, window.first.description, window.last.description])
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT day, json_extract(json, '$.activityClassSeconds') AS classes FROM raw_export
                    WHERE kind = 'dailySummary' AND day >= ? AND day <= ? ORDER BY day
                    """, arguments: [window.first.description, window.last.description])
            let decoder = JSONDecoder()
            let days: [FitnessDay] = rows.compactMap { row in
                guard let day = DayKey(row["day"] as String), let text: String = row["classes"],
                    let seconds = try? decoder.decode([String: Int].self, from: Data(text.utf8))
                else { return nil }
                return FitnessDay(day: day, classSeconds: seconds)
            }
            return FitnessInputs(profile: profile, restingHeartRates: nights, days: days)
        }.values(in: writer)
    }

    /// One metric kind for the `days` nights ending on `night`, oldest first.
    public func observeMetricHistory(_ kind: String, endingOn night: DayKey, days: Int) -> some AsyncSequence<[ComputedMetric], any Error> {
        ValueObservation.tracking { db in
            try ComputedMetricRecord
                .filter(
                    sql: "kind = ? AND day >= ? AND day <= ? AND hour IS NULL",
                    arguments: [kind, night.adding(days: -(days - 1)).description, night.description]
                )
                .order(sql: "day")
                .fetchAll(db)
                .map { try $0.model() }
        }.values(in: writer)
    }

    static func nightReport(_ db: Database, _ night: DayKey) throws -> NightReport? {
        let sleep = try SleepNightRecord.fetchOne(db, key: night.description)?.model()
        let recharge = try NightlyRechargeRecord.fetchOne(db, key: night.description)?.model()
        let metrics =
            try ComputedMetricRecord
            .filter(sql: "day = ? AND hour IS NULL", arguments: [night.description])
            .fetchAll(db)
            .map { try $0.model() }
        if sleep == nil && recharge == nil && metrics.isEmpty { return nil }
        return NightReport(night: night, sleep: sleep, recharge: recharge, metrics: Dictionary(uniqueKeysWithValues: metrics.map { ($0.kind, $0) }))
    }

    /// The night shown for `day`. Today (or later): the newest night up to today, so before last night is in it is the
    /// night before. A past day: that day's own night, nil when it has none.
    static func shownNight(_ db: Database, day: DayKey, today: DayKey) throws -> DayKey? {
        let nights = "SELECT night FROM sleep_night UNION SELECT night FROM nightly_recharge"
        if day >= today {
            return try String.fetchOne(db, sql: "SELECT MAX(night) FROM (\(nights)) WHERE night <= ?", arguments: [today.description])
                .flatMap(DayKey.init)
        }
        return try String.fetchOne(db, sql: "SELECT night FROM (\(nights)) WHERE night = ?", arguments: [day.description])
            .flatMap(DayKey.init)
    }

    static func firstDay(_ db: Database, zone: TimeZone) throws -> DayKey? {
        let night = try String.fetchOne(
            db,
            sql: """
                SELECT MIN(night) FROM (SELECT night FROM sleep_night UNION SELECT night FROM nightly_recharge)
                """
        ).flatMap(DayKey.init)
        let heartRate = try Int64.fetchOne(db, sql: "SELECT MIN(ts) FROM hr_sample").map { DayKey(Date(unixSeconds: $0), in: zone) }
        return [night, heartRate].compactMap { $0 }.min()
    }

    static func todaySnapshot(_ db: Database, day: DayKey, today: DayKey) throws -> TodaySnapshot {
        let isToday = day >= today
        let latestKey = try shownNight(db, day: day, today: today)
        let latest = try latestKey.flatMap { try nightReport(db, $0) }
        let earlier =
            try latestKey.map { key in
                try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(*) FROM (SELECT night FROM sleep_night UNION SELECT night FROM nightly_recharge)
                        WHERE night < ? AND night >= ?
                        """, arguments: [key.description, key.adding(days: -PersonalRange.windowNights).description])!
            } ?? 0
        let heartRate = try isToday ? HeartRateSampleRecord.order(sql: "ts DESC").fetchOne(db)?.model : nil
        let stressNow =
            try isToday
            ? ComputedMetricRecord
                .filter(sql: "kind = ? AND day <= ?", arguments: [MetricKind.stressNow, today.description])
                .order(sql: "day DESC")
                .fetchOne(db)
                .flatMap { try $0.model() }
                .flatMap(StressNow.init) : nil
        let night = try latestKey.flatMap { try dayLines(db, from: $0, through: $0)[$0] } ?? .empty
        let calmDay = isToday ? today : day
        let calm = try dayLines(db, from: calmDay, through: calmDay)[calmDay] ?? .empty
        let steps = try Int.fetchOne(db, sql: "SELECT steps FROM activity_day WHERE day = ? AND steps > 0", arguments: [calmDay.description])
        let stepsReadAt =
            try isToday && steps != nil
            ? Int64.fetchOne(
                db, sql: "SELECT stored_at FROM band_ledger WHERE day = ? AND fetch_kind = ?",
                arguments: [today.description, FetchKind.dailySummary.rawValue]
            ).map(Date.init(unixSeconds:)) : nil
        let lines = DayLines(
            recovery: night.recovery, sleep: night.sleep, calm: calm.calm,
            indicator: night.indicator, asleepMinutes: night.asleepMinutes, highMinutes: calm.highMinutes
        )
        let young = isToday && [lines.recovery, lines.sleep, lines.calm].contains { $0.state == .none || $0.state.isLearning }
        return TodaySnapshot(
            latest: latest, lines: lines, earlierNights: earlier, steps: steps, stepsReadAt: stepsReadAt, latestHeartRate: heartRate,
            stressNow: stressNow, stressDays: try stressBaselineDays(db, before: calmDay),
            alerts: try alertEvents(db, day: calmDay).filter(\.kind.isWarning),
            firstWeek: young ? try firstWeek(db, shownNight: latestKey, today: today, lines: lines) : nil,
            morningReportOn: try alertSettings(db).isOn(.morningReport),
            yesterdayWorkout: isToday ? try yesterdayWorkout(db, today: today) : nil
        )
    }

    /// Every night with sleep or a Nightly Recharge, every night with sleep and each day's clean stress readings:
    /// only those columns.
    static func firstWeek(_ db: Database, shownNight: DayKey?, today: DayKey, lines: DayLines) throws -> FirstWeek? {
        let nights = Set(try String.fetchAll(db, sql: "SELECT night FROM sleep_night UNION SELECT night FROM nightly_recharge").compactMap(DayKey.init))
        let sleepNights = Set(try String.fetchAll(db, sql: "SELECT night FROM sleep_night").compactMap(DayKey.init))
        let rows = try Row.fetchAll(db, sql: "SELECT day, value FROM computed_metric WHERE kind = ?", arguments: [MetricKind.stressReadings])
        let readings = Dictionary(rows.compactMap { row in DayKey(row["day"] as String).map { ($0, Int(row["value"] as Double)) } }, uniquingKeysWith: max)
        return FirstWeek.make(nights: nights, sleepNights: sleepNights, readings: readings, shownNight: shownNight, today: today, lines: lines)
    }

    /// Every day from `first` through `last`, each judged by `InRange` against the 28 days before it. A stress day
    /// counts only with at least `StressThresholds.minimumWindowsPerDay` clean readings; such a day from before the
    /// stress baseline was ready (no high-stress minutes) shows the calm line learning.
    static func dayLines(_ db: Database, from first: DayKey, through last: DayKey) throws -> [DayKey: DayLines] {
        let window = PersonalRange.windowNights
        let start = first.adding(days: -window)
        func metrics(_ kind: String, from: DayKey) throws -> [DayKey: ComputedMetric] {
            let rows =
                try ComputedMetricRecord
                .filter(sql: "kind = ? AND day >= ? AND day <= ? AND hour IS NULL", arguments: [kind, from.description, last.description])
                .fetchAll(db)
                .map { try $0.model() }
            return Dictionary(rows.map { ($0.day, $0) }, uniquingKeysWith: { _, newer in newer })
        }
        let statuses = try metrics(MetricKind.recoveryStatus, from: first).compactMapValues(RecoveryStatus.init)
        let sleeps = try metrics(Contributor.sleep.kind, from: first).compactMapValues(ContributorReading.init)
        let readings = try metrics(MetricKind.stressReadings, from: start).mapValues { Int($0.value) }
        func wellWorn(_ day: DayKey) -> Bool { (readings[day] ?? 0) >= StressThresholds.minimumWindowsPerDay }
        let highMinutes = try metrics(MetricKind.stressHighMinutes, from: start)
        let counted = highMinutes.filter { wellWorn($0.key) }.mapValues(\.value)
        let nights = Set(
            try String.fetchAll(
                db,
                sql: """
                    SELECT night FROM sleep_night WHERE night >= ? AND night <= ?
                    UNION SELECT night FROM nightly_recharge WHERE night >= ? AND night <= ?
                    """, arguments: [start.description, last.description, start.description, last.description]
            ).compactMap(DayKey.init))

        var result: [DayKey: DayLines] = [:]
        var day = first
        while day <= last {
            let before = (1...window).map { day.adding(days: -$0) }
            let minutes = counted[day]
            let calm =
                highMinutes[day] == nil && wellWorn(day)
                ? InRange.calmBeforeBaseline(baselineDays: StressBaseline.qualifyingDays(before: day, counts: readings))
                : InRange.calm(minutes: minutes, previous: before.compactMap { counted[$0] })
            result[day] = DayLines(
                recovery: InRange.recovery(status: statuses[day], earlierNights: before.filter(nights.contains).count),
                sleep: InRange.sleep(sleeps[day]),
                calm: calm,
                indicator: statuses[day]?.indicator, asleepMinutes: sleeps[day]?.value, highMinutes: minutes
            )
            day = day.adding(days: 1)
        }
        return result
    }

    static func stressBaselineDays(_ db: Database, before day: DayKey) throws -> Int {
        let rows = try Row.fetchAll(
            db, sql: "SELECT day, value FROM computed_metric WHERE kind = ? AND day < ? AND day >= ?",
            arguments: [
                MetricKind.stressReadings, day.description, day.adding(days: -StressThresholds.baselineDays).description,
            ])
        let counts = Dictionary(uniqueKeysWithValues: rows.compactMap { row in DayKey(row["day"] as String).map { ($0, Int(row["value"] as Double)) } })
        return StressBaseline.qualifyingDays(before: day, counts: counts)
    }

    static func stressReport(_ db: Database, day: DayKey) throws -> StressReport {
        let metrics =
            try ComputedMetricRecord
            .filter(sql: "day = ? AND method = ?", arguments: [day.description, Stress.method])
            .order(sql: "hour")
            .fetchAll(db)
            .map { try $0.model() }
        return StressReport(
            day: day,
            readings: metrics.first { $0.kind == MetricKind.stressReadings },
            hourly: metrics.filter { $0.kind == MetricKind.stressHourly },
            emptyHours: metrics.compactMap(StressEmptyHour.init),
            highMinutes: metrics.first { $0.kind == MetricKind.stressHighMinutes },
            now: metrics.first { $0.kind == MetricKind.stressNow }.flatMap(StressNow.init),
            baselineDays: try stressBaselineDays(db, before: day)
        )
    }

    static func sleepStages(_ db: Database, endingOn night: DayKey, days: Int) throws -> [NightStages] {
        let stages = [SleepState.deep, .light, .rem].map(MetricKind.sleepStage)
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT day, kind, value FROM computed_metric
                WHERE kind IN (?, ?, ?) AND day >= ? AND day <= ? AND hour IS NULL ORDER BY day
                """,
            arguments: StatementArguments(stages + [night.adding(days: -(days - 1)).description, night.description])
        )
        var minutes: [DayKey: [String: Double]] = [:]
        for row in rows {
            guard let day = DayKey(row["day"] as String) else { continue }
            minutes[day, default: [:]][row["kind"]] = row["value"]
        }
        return minutes.keys.sorted().map { day in
            let found = minutes[day] ?? [:]
            return NightStages(
                night: day, deep: found[MetricKind.sleepStage(.deep)] ?? 0, light: found[MetricKind.sleepStage(.light)] ?? 0,
                rem: found[MetricKind.sleepStage(.rem)] ?? 0)
        }
    }

    static func trends(_ db: Database, today: DayKey, kinds: [String] = TrendsSnapshot.kinds) throws -> TrendsSnapshot {
        var series: [String: [ComputedMetric]] = [:]
        for kind in kinds where kind != MetricKind.steps {
            series[kind] =
                try ComputedMetricRecord
                .filter(
                    sql: "kind = ? AND day > ? AND day <= ? AND hour IS NULL",
                    arguments: [kind, today.adding(days: -TrendsSnapshot.days).description, today.description]
                )
                .order(sql: "day")
                .fetchAll(db)
                .map { try $0.model() }
        }
        guard kinds.contains(MetricKind.steps) else { return TrendsSnapshot(series: series) }
        let steps = try Row.fetchAll(
            db,
            sql: """
                SELECT a.day, a.steps, l.stored_at FROM activity_day AS a
                LEFT JOIN band_ledger AS l ON l.day = a.day AND l.fetch_kind = ?
                WHERE a.steps > 0 AND a.day > ? AND a.day <= ? ORDER BY a.day
                """, arguments: [FetchKind.dailySummary.rawValue, today.adding(days: -TrendsSnapshot.days).description, today.description])
        series[MetricKind.steps] = steps.compactMap { row in
            DayKey(row["day"] as String).map {
                DailySteps.metric(day: $0, steps: row["steps"], readAt: (row["stored_at"] as Int64?).map(Date.init(unixSeconds:)) ?? .distantPast)
            }
        }
        return TrendsSnapshot(series: series)
    }
}
