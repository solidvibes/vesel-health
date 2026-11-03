import Foundation
import GRDB
import VeselCore

/// One workout as the band gave it, typed. `stored_at` is bookkeeping, so an unchanged re-read keeps its backup mark.
struct WorkoutRecord: UpsertRecord {
    static let databaseTableName = "workout"
    static let keyColumns: Set<String> = ["session"]
    static let bookkeepingColumns: Set<String> = ["stored_at"]

    var session: String
    var startAt: Int64
    var endAt: Int64
    var day: String
    var utcOffsetSeconds: Int
    var bandSportId: Int?
    var durationSeconds: Int
    var calories: Int?
    var cardioLoad: Double?
    var cardioLoadRating: Int?
    var trainingLoad: Double?
    var hrAvg: Int?
    var hrMax: Int?
    var hrJson: String?
    var fileSize: Int64
    var unreadableFiles: String?
    var storedAt: Int64

    init(_ workout: Workout, storedAt: Date) throws {
        session = workout.session
        startAt = workout.start.unixSeconds
        endAt = workout.end.unixSeconds
        day = workout.day.description
        utcOffsetSeconds = workout.utcOffsetSeconds
        bandSportId = workout.bandSportId
        durationSeconds = workout.durationSeconds
        calories = workout.calories
        cardioLoad = workout.cardioLoad
        cardioLoadRating = workout.cardioLoadRating
        trainingLoad = workout.trainingLoad
        hrAvg = workout.averageHeartRate
        hrMax = workout.maxHeartRate
        hrJson = try workout.heartRates.map(StoredJSON.encode)
        fileSize = workout.fileSize
        unreadableFiles = workout.unreadableFiles.isEmpty ? nil : workout.unreadableFiles.joined(separator: ",")
        self.storedAt = storedAt.unixSeconds
    }

    func model() throws -> Workout {
        Workout(
            session: session,
            start: Date(unixSeconds: startAt),
            end: Date(unixSeconds: endAt),
            utcOffsetSeconds: utcOffsetSeconds,
            bandSportId: bandSportId,
            durationSeconds: durationSeconds,
            calories: calories,
            cardioLoad: cardioLoad,
            cardioLoadRating: cardioLoadRating,
            trainingLoad: trainingLoad,
            averageHeartRate: hrAvg,
            maxHeartRate: hrMax,
            heartRates: try hrJson.map { try StoredJSON.decode(WorkoutHeartRates.self, from: $0) },
            fileSize: fileSize,
            unreadableFiles: unreadableFiles.map { $0.split(separator: ",").map(String.init) } ?? []
        )
    }
}

/// One file of a workout, as the Polar SDK handed it over.
struct WorkoutFileRecord: UpsertRecord {
    static let databaseTableName = "workout_file"
    static let keyColumns: Set<String> = ["session", "name"]
    static let bookkeepingColumns: Set<String> = ["fetched_at"]

    var session: String
    var name: String
    var data: Data
    var fetchedAt: Int64

    init(_ file: WorkoutFile, session: String, fetchedAt: Date) {
        self.session = session
        name = file.name
        data = file.data
        self.fetchedAt = fetchedAt.unixSeconds
    }
}

/// The owner's fix to a workout. Only the owner writes it; a band read never does.
struct WorkoutChoiceRecord: UpsertRecord {
    static let databaseTableName = "workout_choice"
    static let keyColumns: Set<String> = ["session"]
    static let bookkeepingColumns: Set<String> = ["chosen_at"]

    var session: String
    var sport: String?
    var hidden: Bool
    var chosenAt: Int64

    init(_ choice: WorkoutChoice) {
        session = choice.session
        sport = choice.sport?.rawValue
        hidden = choice.hidden
        chosenAt = choice.chosenAt.unixSeconds
    }

    var model: WorkoutChoice {
        WorkoutChoice(session: session, sport: sport.flatMap(WorkoutSport.init(rawValue:)), hidden: hidden, chosenAt: Date(unixSeconds: chosenAt))
    }
}
