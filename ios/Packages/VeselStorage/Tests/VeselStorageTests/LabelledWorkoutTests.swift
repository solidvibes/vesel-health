import Foundation
import Testing
import VeselCore
@testable import VeselStorage

/// Workouts as the screens get them: labelled on read from the owner's fix, the Loop's sport, the phone's route or the
/// owner's own earlier workouts; "Not a workout" ones left out of a day; the page falls back to the 24/7 heart rate.
struct LabelledWorkoutTests {
    let database: AppDatabase
    let now = at("2026-11-03T09:00:00Z")
    let day = DayKey("2026-11-03")!

    init() throws {
        database = try AppDatabase.inMemory()
    }

    func band(_ session: String, start: String, minutes: Int = 42, sport: Int? = nil, heartRates: WorkoutHeartRates? = nil) -> BandWorkout {
        let begin = at(start)
        return BandWorkout(
            workout: Workout(
                session: session, start: begin, end: begin.addingTimeInterval(Double(minutes * 60)), utcOffsetSeconds: 3600,
                bandSportId: sport, durationSeconds: minutes * 60, calories: nil, cardioLoad: 90, cardioLoadRating: 3, trainingLoad: nil,
                averageHeartRate: nil, maxHeartRate: nil, heartRates: heartRates, fileSize: 1, unreadableFiles: []),
            files: [])
    }

    func shown(_ day: DayKey) async throws -> [LabelledWorkout] {
        for try await value in database.observeLabelledWorkouts(day: day) { return value }
        return []
    }

    func detail(_ session: String) async throws -> WorkoutDetail? {
        for try await value in database.observeWorkout(session: session) { return value }
        return nil
    }

    @Test func aWorkoutWithoutASportIsGuessedFromYourEarlierOnesAtThatTimeOfDay() async throws {
        // Two rides the Loop named and one run the owner named, all around 07:00 local time in the weeks before.
        try await database.save(band("20261020/070500", start: "2026-10-20T06:05:00Z", sport: 2), storedAt: now)
        try await database.save(band("20261027/065000", start: "2026-10-27T05:50:00Z", sport: 2), storedAt: now)
        try await database.save(band("20261029/071500", start: "2026-10-29T06:15:00Z"), storedAt: now)
        try await database.setChoice(WorkoutChoice(session: "20261029/071500", sport: .running, hidden: false, chosenAt: now))
        try await database.save(band("20261103/071000", start: "2026-11-03T06:10:00Z"), storedAt: now)

        let today = try await shown(day)
        #expect(today.map(\.label) == [WorkoutLabel(sport: .cycling, source: .timeOfDay, hidden: false)])
        #expect(today.first?.span.word == "ride")

        // Without cycling in Your sports, the guess comes from the sports left.
        try await database.setWorkoutSports([.running, .swimming])
        #expect(try await shown(day).map(\.label) == [WorkoutLabel(sport: .running, source: .timeOfDay, hidden: false)])
    }

    @Test func aRouteCoveringTheWorkoutGuessesFromItsSpeedAndNotAWorkoutLeavesTheDay() async throws {
        try await database.save(band("20261103/071000", start: "2026-11-03T06:10:00Z"), storedAt: now)
        try await database.save(band("20261103/180000", start: "2026-11-03T17:00:00Z"), storedAt: now)
        try await database.setChoice(WorkoutChoice(session: "20261103/180000", sport: nil, hidden: true, chosenAt: now))
        // 0.0005° of latitude (55.6 m) every 5 s is 40 km/h, over the whole 42 minutes.
        let begin = at("2026-11-03T06:10:00Z")
        let points = (0...(42 * 12)).map {
            RoutePoint(time: begin.addingTimeInterval(Double($0) * 5), latitude: 52.5 + Double($0) * 0.0005, longitude: 13.4, accuracy: 5)
        }
        try await database.save(RecordedRoute(start: begin, end: begin.addingTimeInterval(42 * 60), points: points), updatedAt: now)

        let today = try await shown(day)
        #expect(today.map(\.workout.session) == ["20261103/071000"])
        #expect(today.first?.label == WorkoutLabel(sport: .cycling, source: .speed, hidden: false))
        #expect(today.first?.route?.points.count == 42 * 12 + 1)

        // The page still finds the hidden one, to say so and go back.
        #expect(try await detail("20261103/180000")?.labelled.label.hidden == true)
    }

    @Test func thePageUsesTheDaysHeartRateOnlyWhenTheWorkoutHadNone() async throws {
        try await database.save(heartRates: [
            HeartRateSample(time: at("2026-11-03T06:09:00Z"), bpm: 70, trigger: .timed),
            HeartRateSample(time: at("2026-11-03T06:20:00Z"), bpm: 141, trigger: .timed),
            HeartRateSample(time: at("2026-11-03T06:52:00Z"), bpm: 150, trigger: .timed),
        ])
        try await database.save(band("20261103/071000", start: "2026-11-03T06:10:00Z"), storedAt: now)
        try await database.save(
            band("20261103/180000", start: "2026-11-03T17:00:00Z", heartRates: WorkoutHeartRates(intervalMs: 1000, bpm: [120, 130])), storedAt: now)

        #expect(try await detail("20261103/071000")?.dayHeartRates.map(\.bpm) == [141, 150])
        #expect(try await detail("20261103/180000")?.dayHeartRates.isEmpty == true)
        #expect(try await detail("20261103/090000") == nil)
    }
}
