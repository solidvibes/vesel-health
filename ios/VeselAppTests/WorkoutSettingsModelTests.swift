import Foundation
import Testing
import VeselCore
import VeselStorage
import VeselWearable
import VeselWearableTesting
@testable import Vesel

/// Workouts settings: a band change goes to the Loop first, then the phone; one the Loop refuses changes nothing and puts the
/// control back.
@MainActor
struct WorkoutSettingsModelTests {
    let stored = WorkoutDetection(isOn: true, sensitivity: 50, minimumMinutes: 10)

    func model(failure: FakeFailure? = nil) async throws -> (WorkoutSettingsModel, FakeWearableSource, AppDatabase) {
        let database = try AppDatabase.inMemory()
        let band = try FakeWearableSource(scenario: .normal, failure: failure)
        let clock = FixedClock(now: try Date("2026-11-03T09:00:00Z", strategy: .iso8601), timeZone: .gmt)
        let bandSync = BandSync(band: band, database: database, clock: clock)
        let pipeline = SyncPipeline(bandSync: bandSync, database: database, clock: clock, status: SyncStatusStore(defaults: .throwaway()))
        try await database.storeWorkoutDetection(stored)
        await band.setDetection(stored)
        let model = WorkoutSettingsModel(
            database: database, idle: { await pipeline.idle() }, writeDetection: { await pipeline.writeWorkoutDetection($0) })
        await model.load()
        return (model, band, database)
    }

    @Test func aChangeReachesTheLoopThenThePhone() async throws {
        let (model, band, database) = try await model()
        let changed = WorkoutDetection(isOn: true, sensitivity: 80, minimumMinutes: 20)

        await model.setDetection(changed)

        #expect(await band.detection == changed)
        #expect(try await database.workoutDetection() == changed)
        #expect(model.detection == changed)
        #expect(model.failed == nil)
    }

    @Test func aRefusedChangeKeepsThePhoneAndPutsTheControlBack() async throws {
        let (model, band, database) = try await model(failure: .workoutDetection)
        let changed = WorkoutDetection(isOn: false, sensitivity: 50, minimumMinutes: 10)

        await model.setDetection(changed)

        #expect(await band.detection == stored)
        #expect(try await database.workoutDetection() == stored)
        #expect(model.detection == stored)
        #expect(model.failed == changed)
    }
}
