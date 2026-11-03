import Foundation
import GRDB
import VeselCore

/// A stored workout with the owner's fix, if any. A hidden one ("Not a workout") carries the flag in its choice.
public struct StoredWorkout: Sendable, Equatable {
    public var workout: Workout
    public var choice: WorkoutChoice?

    public var isHidden: Bool { choice?.hidden ?? false }
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

    /// Stores the owner's fix. A band read never writes it.
    public func setChoice(_ choice: WorkoutChoice) async throws {
        try await writer.write { try WorkoutChoiceRecord(choice).upsert($0) }
    }

    static func workouts(_ db: Database, from first: DayKey, through last: DayKey) throws -> [StoredWorkout] {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT w.session, w.start_at, w.end_at, w.day, w.utc_offset_seconds, w.band_sport_id, w.duration_seconds, w.calories,
                       w.cardio_load, w.cardio_load_rating, w.training_load, w.hr_avg, w.hr_max, w.hr_json, w.file_size,
                       w.unreadable_files, w.stored_at,
                       c.sport AS choice_sport, c.hidden AS choice_hidden, c.chosen_at AS choice_chosen_at
                FROM workout AS w LEFT JOIN workout_choice AS c ON c.session = w.session
                WHERE w.day >= ? AND w.day <= ?
                ORDER BY w.start_at, w.session
                """,
            arguments: [first.description, last.description]
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
        guard let value = try await setting(Self.workoutSportsKey) else { return Set(WorkoutSport.allCases) }
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
        let earliest = interval.start.addingTimeInterval(-WorkoutThresholds.routeMaxHours * 3600)
        return try await writer.read { db in
            try WorkoutRouteRecord
                .filter(sql: "started_at >= ? AND started_at <= ?", arguments: [earliest.unixSeconds, interval.end.unixSeconds])
                .order(sql: "started_at")
                .fetchAll(db)
                .map { try $0.model() }
                .filter { $0.interval.intersects(interval) }
        }
    }

    /// The route that overlaps the workout most; nil when none does.
    public func route(for workout: Workout) async throws -> RecordedRoute? {
        let window = DateInterval(start: workout.start, end: max(workout.start, workout.end))
        return try await routes(overlapping: window)
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
