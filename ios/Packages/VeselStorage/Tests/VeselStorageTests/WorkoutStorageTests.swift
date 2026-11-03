import Foundation
import GRDB
import Testing
import VeselCore
@testable import VeselStorage

struct WorkoutStorageTests {
    let database: AppDatabase
    let now = at("2026-11-03T09:00:00Z")

    init() throws {
        database = try AppDatabase.inMemory()
    }

    func run(session: String = "20261103/071000", start: String = "2026-11-03T06:10:00Z", fileSize: Int64 = 4_000) -> BandWorkout {
        let begin = at(start)
        return BandWorkout(
            workout: Workout(
                session: session, start: begin, end: begin.addingTimeInterval(42 * 60), utcOffsetSeconds: 3600, bandSportId: 1,
                durationSeconds: 42 * 60, calories: 410, cardioLoad: 87, cardioLoadRating: 3, trainingLoad: 64, averageHeartRate: 148,
                maxHeartRate: 171, heartRates: WorkoutHeartRates(intervalMs: 1000, bpm: [120, 131, 140]), fileSize: fileSize,
                unreadableFiles: []
            ),
            files: [
                WorkoutFile(name: "TSESS", data: Data([0x08, 0x01])),
                WorkoutFile(name: "00/BASE", data: Data([0x0A, 0x02, 0x10, 0x20])),
                WorkoutFile(name: "00/SAMPLES", data: Data([0xFF])),
            ]
        )
    }

    @Test func aWorkoutIsStoredWithItsFilesAndBelongsToTheDayItStarted() async throws {
        // 23:30 UTC on Nov 2 is 00:30 on Nov 3 at UTC+1.
        let late = run(session: "20261103/003000", start: "2026-11-02T23:30:00Z")
        try await database.save(late, storedAt: now)

        let stored = try await database.workouts(day: DayKey("2026-11-03")!)
        #expect(stored == [StoredWorkout(workout: late.workout, choice: nil)])
        #expect(try await database.workouts(day: DayKey("2026-11-02")!).isEmpty)
        #expect(try await database.storedWorkouts() == ["20261103/003000": 4_000])
        let files = try await database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT name, data FROM workout_file ORDER BY name").map { ($0["name"] as String, $0["data"] as Data) }
        }
        #expect(files.map(\.0) == ["00/BASE", "00/SAMPLES", "TSESS"])
        #expect(files.map(\.1) == [Data([0x0A, 0x02, 0x10, 0x20]), Data([0xFF]), Data([0x08, 0x01])])
    }

    @Test func anUnchangedReReadKeepsTheBackupMarkAndTheOwnersChoice() async throws {
        try await database.save(run(), storedAt: now)
        let choice = WorkoutChoice(session: "20261103/071000", sport: .cycling, hidden: false, chosenAt: now)
        try await database.setChoice(choice)
        try await database.markAllUploaded(at: 1_000)

        try await database.save(run(), storedAt: now.addingTimeInterval(3600))

        #expect(try await database.pendingUploadCount(now: now) == 0)
        #expect(try await database.workouts(day: DayKey("2026-11-03")!).first?.choice == choice)
    }

    @Test func aChangedReReadGoesToTheBackupAgainAndKeepsTheChoice() async throws {
        try await database.save(run(), storedAt: now)
        try await database.setChoice(WorkoutChoice(session: "20261103/071000", sport: nil, hidden: true, chosenAt: now))
        try await database.markAllUploaded(at: 1_000)

        var changed = run(fileSize: 5_000)
        changed.workout.cardioLoad = nil
        changed.workout.unreadableFiles = ["00/ROUTE"]
        changed.files.removeLast()
        try await database.save(changed, storedAt: now.addingTimeInterval(3600))

        let stored = try #require(try await database.workouts(day: DayKey("2026-11-03")!).first)
        #expect(stored.workout == changed.workout)
        #expect(stored.isHidden)
        #expect(try await database.uploadedAt("workout", where: "1") == nil)
        #expect(try await database.uploadedAt("workout_choice", where: "1") == 1_000)
        // A file the band no longer has goes; the ones left are unchanged and keep their mark.
        #expect(try await database.count("workout_file") == 2)
        #expect(try await database.pendingUploadCount(now: now) == 1)
    }

    @Test func rowsGoToTheMacWithTheirSessionKeysAndFilesAsBase64() async throws {
        try await database.save(run(), storedAt: now)
        try await database.setChoice(WorkoutChoice(session: "20261103/071000", sport: .running, hidden: false, chosenAt: now))

        let workout = try #require(try await database.pendingUploads(.workout, limit: 10, now: now).first)
        #expect(workout.key == "20261103/071000")
        #expect(workout.data["cardio_load"] == .real(87))
        #expect(workout.data["cardio_load_rating"] == .integer(3))
        #expect(workout.data["unreadable_files"] == .null)
        #expect(workout.data["uploaded_at"] == nil)

        let files = try await database.pendingUploads(.workoutFile, limit: 10, now: now)
        #expect(files.map(\.key).sorted() == ["20261103/071000/00/BASE", "20261103/071000/00/SAMPLES", "20261103/071000/TSESS"])
        #expect(files.first { $0.key.hasSuffix("BASE") }?.data["data"] == .text(Data([0x0A, 0x02, 0x10, 0x20]).base64EncodedString()))

        let choice = try #require(try await database.pendingUploads(.workoutChoice, limit: 10, now: now).first)
        #expect(choice.key == "20261103/071000")
        #expect(choice.data["sport"] == .text("running"))
    }

    @Test func forgettingTheBandResetsDetectionAndKeepsWorkouts() async throws {
        try await database.save(run(), storedAt: now)
        try await database.storeWorkoutDetection(WorkoutDetection(isOn: true, sensitivity: 70, minimumMinutes: 15))
        #expect(try await database.isWorkoutDetectionSetUp())
        #expect(try await database.workoutDetection() == WorkoutDetection(isOn: true, sensitivity: 70, minimumMinutes: 15))

        try await database.forgetBand(at: now)

        #expect(try await !database.isWorkoutDetectionSetUp())
        #expect(try await database.workoutDetection() == nil)
        #expect(try await database.count("workout") == 1)
        #expect(try await database.count("workout_file") == 3)
    }
}
