import Foundation
import GRDB
import VeselCore

/// The reads a day's stress readings are worked out from, shared by the stress pass and the screens that work them out on read.
enum StressInputs {
    static func daysWithBeats(_ db: Database) throws -> Set<DayKey> {
        Set(try String.fetchAll(db, sql: "SELECT DISTINCT day FROM ppi_session").compactMap(DayKey.init))
    }

    static func sessions(_ db: Database, day: DayKey) throws -> [PPISession] {
        try Row.fetchAll(
            db, sql: "SELECT id, start_ts, trigger, utc_offset_seconds FROM ppi_session WHERE day = ? ORDER BY start_ts", arguments: [day.description]
        ).map { row in
            let samples = try Row.fetchAll(
                db, sql: "SELECT ts_ms, interval_ms, error_ms, blocker, skin_contact FROM ppi_sample WHERE session_id = ? ORDER BY ts_ms",
                arguments: [row["id"] as Int64]
            ).map { sample in
                PPISample(
                    time: Date(unixMilliseconds: sample["ts_ms"]), intervalMs: sample["interval_ms"], errorMs: sample["error_ms"],
                    blocker: sample["blocker"], skinContact: sample["skin_contact"]
                )
            }
            return PPISession(
                start: Date(unixSeconds: row["start_ts"]), trigger: PPITrigger(rawValue: row["trigger"]) ?? .unknown,
                utcOffsetSeconds: row["utc_offset_seconds"], samples: samples
            )
        }
    }

    static func heartRates(_ db: Database, day: DayKey, zone: TimeZone) throws -> [HeartRateSample] {
        try HeartRateSampleRecord
            .filter(sql: "ts >= ? AND ts < ?", arguments: [day.start(in: zone).unixSeconds, day.adding(days: 1).start(in: zone).unixSeconds])
            .order(sql: "ts")
            .fetchAll(db)
            .map(\.model)
    }

    /// What counts as exercise: resting heart rate + 40 % of the reserve, from the latest nightly resting heart rate up to a day and 220 − age.
    struct ActivityLimits {
        let birthYear: Int?
        let resting: [DayKey: Double]

        init(birthYear: Int?, resting: [DayKey: Double]) {
            self.birthYear = birthYear
            self.resting = resting
        }

        init(_ db: Database) throws {
            birthYear = try Int.fetchOne(db, sql: "SELECT birth_year FROM profile")
            resting = Dictionary(
                uniqueKeysWithValues: try Row.fetchAll(
                    db, sql: "SELECT day, value FROM computed_metric WHERE kind = ? AND hour IS NULL", arguments: [Contributor.restingHeartRate.kind]
                )
                .compactMap { row in DayKey(row["day"] as String).map { ($0, row["value"] as Double) } }
            )
        }

        func heartRate(on day: DayKey) -> Double? {
            guard let birthYear, let latest = resting.keys.filter({ $0 <= day }).max(), let rate = resting[latest] else { return nil }
            let maximum = Double(220 - (day.year - birthYear))
            return rate + StressThresholds.activityReserveShare * (maximum - rate)
        }
    }
}

extension AppDatabase {
    /// Every daytime reading of the days `first` through `last` with its level, worked out on read against each day's stored
    /// baseline and floor, oldest first. A day still learning gives none; a reading after the clock's now is left out.
    /// Runs again only when the stress pass rewrites a day's `stress.readings` (its day or time), not on every stored beat.
    public func observeStressReadings(from first: DayKey, through last: DayKey, clock: any VeselClock) -> some AsyncSequence<[StressReading], any Error> {
        let region = SQLRequest<Row>(sql: "SELECT day, computed_at FROM computed_metric WHERE kind = ?", arguments: [MetricKind.stressReadings])
        return ValueObservation.tracking(region: region) { db in
            try Self.stressReadings(db, from: first, through: last, now: clock.now, zone: clock.timeZone)
        }.values(in: writer)
    }

    static func stressReadings(_ db: Database, from first: DayKey, through last: DayKey, now: Date, zone: TimeZone) throws -> [StressReading] {
        let stored = try Row.fetchAll(
            db,
            sql: """
                SELECT day, inputs_json FROM computed_metric WHERE kind = ? AND hour IS NULL AND day >= ? AND day <= ?
                """, arguments: [MetricKind.stressReadings, first.description, last.description])
        var baselines: [DayKey: StressBaseline] = [:]
        for row in stored {
            guard let day = DayKey(row["day"] as String) else { continue }
            let inputs = try StoredJSON.decode(StoredInputs.self, from: row["inputs_json"]).inputs
            baselines[day] = StressBaseline(stored: inputs)
        }
        guard !baselines.isEmpty else { return [] }
        let limits = try StressInputs.ActivityLimits(db)
        var readings: [StressReading] = []
        for (day, baseline) in baselines.sorted(by: { $0.key < $1.key }) {
            let found = Stress.windows(
                sessions: try StressInputs.sessions(db, day: day),
                heartRates: try StressInputs.heartRates(db, day: day, zone: zone),
                activityHeartRate: limits.heartRate(on: day)
            )
            readings += found.windows.filter { $0.start <= now }.map {
                StressReading(start: $0.start, rmssd: $0.rmssd, level: baseline.level(of: $0.value), baseline: baseline)
            }
        }
        return readings.sorted { $0.start < $1.start }
    }
}

/// The inputs half of `inputs_json`; the sentence is left out.
private struct StoredInputs: Decodable {
    var inputs: [Explanation.Input]
}
