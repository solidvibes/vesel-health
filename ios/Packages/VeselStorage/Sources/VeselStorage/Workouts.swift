import Foundation
import GRDB
import VeselCore

/// A stored workout with the owner's fix, if any. A hidden one ("Not a workout") carries the flag in its choice.
public struct StoredWorkout: Sendable, Equatable {
    public var workout: Workout
    public var choice: WorkoutChoice?

    public var isHidden: Bool { choice?.hidden ?? false }
}

/// A stored workout with what it is called and the phone's route over it, worked out on read (never stored).
public struct LabelledWorkout: Sendable, Equatable {
    public var stored: StoredWorkout
    public var label: WorkoutLabel
    /// The route overlapping it most, cut to the workout; nil with none.
    public var route: WorkoutRouteSummary?

    public var workout: Workout { stored.workout }
    public var load: WorkoutLoad? { WorkoutLoad.make(stored.workout) }
    /// Its time and its noun, for a chart block.
    public var span: WorkoutSpan { WorkoutSpan(range: workout.start...max(workout.start, workout.end), word: label.noun) }
}

/// Everything the Workout page shows: the workout, the owner's sports for the sport sheet, and the 24/7 heart rate during it
/// when the Loop's workout file had none.
public struct WorkoutDetail: Sendable, Equatable {
    public var labelled: LabelledWorkout
    public var sports: Set<WorkoutSport>
    /// Empty when the workout has its own heart rate.
    public var dayHeartRates: [HeartRateSample]
}

extension AppDatabase {
    // MARK: Workouts

    /// Stores a workout read off the band in one transaction: its row and its files, dropping files of that workout the
    /// band no longer has. Never touches the owner's choice.
    public func save(_ workout: BandWorkout, storedAt: Date) async throws {
        let record = try WorkoutRecord(workout.workout, storedAt: storedAt)
        let session = workout.workout.session
        try await writer.write { db in
            try record.upsert(db)
            for file in workout.files {
                try WorkoutFileRecord(file, session: session, fetchedAt: storedAt).upsert(db)
            }
            let names = workout.files.map(\.name)
            try db.execute(
                sql: "DELETE FROM workout_file WHERE session = ? AND name NOT IN (\(databaseQuestionMarks(count: names.count)))",
                arguments: StatementArguments([session] + names)
            )
        }
    }

    /// Every stored workout's session and the band's file size when it was read.
    public func storedWorkouts() async throws -> [String: Int64] {
        try await writer.read { db in
            var sizes: [String: Int64] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT session, file_size FROM workout") {
                sizes[row["session"]] = row["file_size"]
            }
            return sizes
        }
    }

    /// The workouts that started on `day`, in time order, with the owner's fixes.
    public func workouts(day: DayKey) async throws -> [StoredWorkout] {
        try await writer.read { try Self.workouts($0, from: day, through: day) }
    }

    /// The workouts that started from `first` through `last`, in time order, with the owner's fixes.
    public func workouts(from first: DayKey, through last: DayKey) async throws -> [StoredWorkout] {
        try await writer.read { try Self.workouts($0, from: first, through: last) }
    }

    public func observeWorkouts(day: DayKey) -> some AsyncSequence<[StoredWorkout], any Error> {
        ValueObservation.tracking { db in try Self.workouts(db, from: day, through: day) }.removeDuplicates().values(in: writer)
    }

    /// The workouts that started on `day`, in time order, labelled; "Not a workout" ones left out.
    public func observeLabelledWorkouts(day: DayKey) -> some AsyncSequence<[LabelledWorkout], any Error> {
        ValueObservation.tracking { db in
            try Self.labelled(db, try Self.workouts(db, from: day, through: day).filter { !$0.isHidden })
        }.removeDuplicates().values(in: writer)
    }

    /// One workout for its page, hidden or not; nil when it isn't stored.
    public func observeWorkout(session: String) -> some AsyncSequence<WorkoutDetail?, any Error> {
        ValueObservation.tracking { db -> WorkoutDetail? in
            guard let stored = try Self.workouts(db, where: "w.session = ?", arguments: [session]).first,
                let labelled = try Self.labelled(db, [stored]).first
            else { return nil }
            let workout = stored.workout
            let dayHeartRates =
                workout.heartRates == nil
                ? try HeartRateSampleRecord
                    .filter(sql: "ts >= ? AND ts <= ?", arguments: [workout.start.unixSeconds, workout.end.unixSeconds])
                    .order(sql: "ts")
                    .fetchAll(db)
                    .map(\.model) : []
            return WorkoutDetail(labelled: labelled, sports: try Self.workoutSports(db), dayHeartRates: dayHeartRates)
        }.removeDuplicates().values(in: writer)
    }

    /// Labels each workout: the owner's fix, the Loop's sport, a guess from the phone's route or from the owner's own
    /// earlier workouts at that time of day (`WorkoutLabel`), in the workout's own time zone.
    static func labelled(_ db: Database, _ workouts: [StoredWorkout]) throws -> [LabelledWorkout] {
        guard let first = workouts.map(\.workout.day).min(), let last = workouts.map(\.workout.day).max() else { return [] }
        let sports = try workoutSports(db)
        let history = try Self.workouts(db, from: first.adding(days: -WorkoutThresholds.guessHistoryDays - 1), through: last)
            .filter { !$0.isHidden }
            .compactMap { earlier -> (start: Date, sport: WorkoutSport)? in
                let sport = earlier.choice?.sport ?? earlier.workout.bandSportId.flatMap(WorkoutSport.init(bandSportId:))
                return sport.map { (earlier.workout.start, $0) }
            }
        return try workouts.map { stored in
            let workout = stored.workout
            let route = try route(db, for: workout).map {
                WorkoutRouteSummary(points: $0.points, workout: workout.interval, durationSeconds: workout.durationSeconds)
            }
            let label = WorkoutLabel.make(
                workout: workout, choice: stored.choice, route: route, history: history, sports: sports,
                zone: TimeZone(secondsFromGMT: workout.utcOffsetSeconds) ?? .gmt
            )
            return LabelledWorkout(stored: stored, label: label, route: route)
        }
    }

    /// Stores the owner's fix. A band read never writes it.
    public func setChoice(_ choice: WorkoutChoice) async throws {
        try await writer.write { try WorkoutChoiceRecord(choice).upsert($0) }
    }

    static func workouts(_ db: Database, from first: DayKey, through last: DayKey) throws -> [StoredWorkout] {
        try workouts(db, where: "w.day >= ? AND w.day <= ?", arguments: [first.description, last.description])
    }

    static func workouts(_ db: Database, where condition: String, arguments: StatementArguments) throws -> [StoredWorkout] {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT w.session, w.start_at, w.end_at, w.day, w.utc_offset_seconds, w.band_sport_id, w.duration_seconds, w.calories,
                       w.cardio_load, w.cardio_load_rating, w.training_load, w.hr_avg, w.hr_max, w.hr_json, w.file_size,
                       w.unreadable_files, w.stored_at,
                       c.sport AS choice_sport, c.hidden AS choice_hidden, c.chosen_at AS choice_chosen_at
                FROM workout AS w LEFT JOIN workout_choice AS c ON c.session = w.session
                WHERE \(condition)
                ORDER BY w.start_at, w.session
                """,
            arguments: arguments
        )
        return try rows.map { row in
            let workout = try WorkoutRecord(row: row).model()
            let choice = (row["choice_chosen_at"] as Int64?).map { chosenAt in
                WorkoutChoice(
                    session: workout.session,
                    sport: (row["choice_sport"] as String?).flatMap(WorkoutSport.init(rawValue:)),
                    hidden: row["choice_hidden"],
                    chosenAt: Date(unixSeconds: chosenAt)
                )
            }
            return StoredWorkout(workout: workout, choice: choice)
        }
    }

    // MARK: Workout detection on the Loop

    /// Set once Vesel has switched on the Loop's automatic training detection. Not uploaded.
    public static let workoutDetectionSetUpKey = "workouts.detectionSetUp"
    /// The Loop's training detection as Vesel last wrote or read it (JSON `WorkoutDetection`). Only Vesel changes it after
    /// pairing, so the phone's copy stays true. Not uploaded.
    public static let workoutDetectionKey = "workouts.detection"

    /// The Loop's training detection as last written or read; nil before the one-time switch-on.
    public func workoutDetection() async throws -> WorkoutDetection? {
        try await writer.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM setting WHERE key = ?", arguments: [Self.workoutDetectionKey])
                .map { try StoredJSON.decode(WorkoutDetection.self, from: $0) }
        }
    }

    /// Whether the one-time switch-on happened.
    public func isWorkoutDetectionSetUp() async throws -> Bool {
        try await setting(Self.workoutDetectionSetUpKey) != nil
    }

    /// Keeps what the Loop now has and marks the one-time switch-on as done, in one transaction.
    public func storeWorkoutDetection(_ detection: WorkoutDetection) async throws {
        try await setSettings([Self.workoutDetectionKey: try StoredJSON.encode(detection), Self.workoutDetectionSetUpKey: "done"])
    }

    // MARK: Workout settings on the phone

    /// The sports guesses and the sport sheet may use (comma list of `WorkoutSport` raw values); absent means all. Not uploaded.
    public static let workoutSportsKey = "workouts.sports"

    /// The owner's sports; all of them until changed.
    public func workoutSports() async throws -> Set<WorkoutSport> {
        try await writer.read { try Self.workoutSports($0) }
    }

    static func workoutSports(_ db: Database) throws -> Set<WorkoutSport> {
        guard let value = try String.fetchOne(db, sql: "SELECT value FROM setting WHERE key = ?", arguments: [workoutSportsKey]) else {
            return Set(WorkoutSport.allCases)
        }
        return Set(value.split(separator: ",").compactMap { WorkoutSport(rawValue: String($0)) })
    }

    public func setWorkoutSports(_ sports: Set<WorkoutSport>) async throws {
        let value = WorkoutSport.allCases.filter(sports.contains).map(\.rawValue).joined(separator: ",")
        try await setSettings([Self.workoutSportsKey: value])
    }

    // MARK: Routes

    /// Stores the route as recorded so far, replacing the earlier write of the same route (keyed by its start).
    public func save(_ route: RecordedRoute, updatedAt: Date) async throws {
        let record = try WorkoutRouteRecord(route, updatedAt: updatedAt)
        try await writer.write { try record.upsert($0) }
    }

    /// The routes that overlap `interval`, in time order. One without an end counts up to its last point. A route stops after
    /// `routeMaxHours`, so only those starting that long before `interval` are read.
    public func routes(overlapping interval: DateInterval) async throws -> [RecordedRoute] {
        try await writer.read { try Self.routes($0, overlapping: interval) }
    }

    static func routes(_ db: Database, overlapping interval: DateInterval) throws -> [RecordedRoute] {
        let earliest = interval.start.addingTimeInterval(-WorkoutThresholds.routeMaxHours * 3600)
        return try WorkoutRouteRecord
            .filter(sql: "started_at >= ? AND started_at <= ?", arguments: [earliest.unixSeconds, interval.end.unixSeconds])
            .order(sql: "started_at")
            .fetchAll(db)
            .map { try $0.model() }
            .filter { $0.interval.intersects(interval) }
    }

    /// The route that overlaps the workout most; nil when none does.
    public func route(for workout: Workout) async throws -> RecordedRoute? {
        try await writer.read { try Self.route($0, for: workout) }
    }

    static func route(_ db: Database, for workout: Workout) throws -> RecordedRoute? {
        let window = workout.interval
        return try routes(db, overlapping: window)
            .map { ($0, $0.interval.intersection(with: window)?.duration ?? 0) }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }?
            .0
    }

    /// Whether "Record my route" is on ("on" / "off"); absent means on. Not uploaded.
    public static let workoutRouteKey = "workouts.route"

    public func isRouteRecordingOn() async throws -> Bool {
        try await setting(Self.workoutRouteKey) != "off"
    }

    public func setRouteRecording(_ on: Bool) async throws {
        try await setSettings([Self.workoutRouteKey: on ? "on" : "off"])
    }
}
