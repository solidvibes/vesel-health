import Foundation
import Testing
import VeselCore
import VeselStorage
@testable import Vesel

/// The Workout page: a guessed sport says so, the owner's fix recomputes stress at once and survives a later read of the Loop,
/// and "Not a workout" closes the page.
@MainActor
struct WorkoutPageModelTests {
    let now = try! Date("2026-11-03T09:00:00Z", strategy: .iso8601)
    let session = "20261103/071000"

    func band(_ session: String, start: String, sport: Int?) throws -> BandWorkout {
        let begin = try Date(start, strategy: .iso8601)
        return BandWorkout(
            workout: Workout(
                session: session, start: begin, end: begin.addingTimeInterval(42 * 60), utcOffsetSeconds: 0, bandSportId: sport,
                durationSeconds: 42 * 60, calories: 410, cardioLoad: 87, cardioLoadRating: 3, trainingLoad: nil, averageHeartRate: 148,
                maxHeartRate: 171, heartRates: WorkoutHeartRates(intervalMs: 1000, bpm: [120, 131, 140]), fileSize: 1, unreadableFiles: []),
            files: [])
    }

    func model() async throws -> (WorkoutPageModel, AppDatabase, Recorded) {
        let database = try AppDatabase.inMemory()
        try await database.save(try band("20261027/070500", start: "2026-10-27T07:05:00Z", sport: 1), storedAt: now)
        try await database.save(try band(session, start: "2026-11-03T07:10:00Z", sport: nil), storedAt: now)
        let recorded = Recorded()
        let model = WorkoutPageModel(
            database: database, clock: FixedClock(now: now, timeZone: .gmt), units: UnitsStore(), session: session,
            recomputeStress: { recorded.days.append($0) })
        return (model, database, recorded)
    }

    @MainActor final class Recorded {
        var days: [Set<DayKey>] = []
    }

    @Test func aGuessedSportSaysSoAndTheFixRecomputesStressAndSurvivesARead() async throws {
        let (model, database, recorded) = try await model()
        await observe(model.observe) { model.isLoaded }
        #expect(model.label == WorkoutLabel(sport: .running, source: .timeOfDay, hidden: false))
        #expect(model.guessChip == "guessed from time of day · change")
        #expect(model.load?.text == "Cardio load 87")

        await model.choose(.cycling)
        #expect(recorded.days == [[DayKey("2026-11-03")!]])

        try await database.save(try band(session, start: "2026-11-03T07:10:00Z", sport: nil), storedAt: now.addingTimeInterval(3600))
        await observe(model.observe) { model.label?.source == .owner }
        #expect(model.label == WorkoutLabel(sport: .cycling, source: .owner, hidden: false))
        #expect(model.guessChip == nil)
    }

    @Test func notAWorkoutHidesItAndClosesThePage() async throws {
        let (model, database, recorded) = try await model()
        await observe(model.observe) { model.isLoaded }

        await model.notAWorkout()

        #expect(model.isClosed)
        #expect(recorded.days.count == 1)
        #expect(try await database.workouts(day: DayKey("2026-11-03")!).first { $0.workout.session == session }?.isHidden == true)
    }
}
