import Foundation
import Testing
import VeselCore
import VeselStorage
import VeselWearable
import VeselWearableTesting
@testable import Vesel

/// Alert switches are kept on the phone; forgetting the Loop reads it one last time, resets it, and only then leaves.
@MainActor
struct LoopSettingsModelTests {
    let now = try! Date("2026-10-26T09:00:00Z", strategy: .iso8601)

    func settings(lastRead: SyncOutcome? = .success, didForget: @escaping () -> Void = {}) async throws -> (LoopSettingsModel, AppDatabase, FakeWearableSource)
    {
        let database = try AppDatabase.inMemory()
        let clock = FixedClock(now: now, timeZone: .gmt)
        let band = try FakeWearableSource(scenario: .normal)
        let bandSync = BandSync(band: band, database: database, clock: clock)
        let pipeline = SyncPipeline(bandSync: bandSync, database: database, clock: clock, status: SyncStatusStore(defaults: .throwaway()))
        try await database.save(BandInfo(deviceId: "FAKE0001", name: "Polar Loop", pairedAt: now.addingTimeInterval(-86_400)))
        let model = LoopSettingsModel(
            database: database, clock: clock, bandSync: bandSync, pipeline: pipeline, forget: nil, backupSetUpError: nil,
            runSync: { lastRead }, didForget: didForget
        )
        return (model, database, band)
    }

    @Test func anAlertSwitchIsSaved() async throws {
        let (model, database, _) = try await settings()
        #expect(model.alerts.isOn(.lowRecovery))

        await model.setAlert(.lowRecovery, on: false)

        #expect(!model.alerts.isOn(.lowRecovery))
        #expect(try await database.alertSettings().isOn(.lowRecovery) == false)
    }

    @Test func forgettingResetsTheLoopThenLeaves() async throws {
        var forgotten = false
        let (model, database, band) = try await settings { forgotten = true }

        await model.confirmForget()

        #expect(model.forget == .done(bandWasReset: true))
        #expect(await band.calls.contains("factoryReset"))
        #expect(try await database.band() == nil)
        #expect(!forgotten)

        model.finishForgetting()
        #expect(forgotten)
        #expect(model.forget == nil)
    }

    @Test func aFinalReadThatFailsKeepsTheLoop() async throws {
        let (model, database, band) = try await settings(lastRead: .unreachable)

        await model.confirmForget()

        #expect(model.forget == .lost(lastRead: nil))
        #expect(await !band.calls.contains("factoryReset"))
        #expect(try await database.band() != nil)
    }
}
