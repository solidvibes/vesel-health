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

    func settings(lastRead: SyncOutcome? = .success, failure: FakeFailure? = nil, didForget: @escaping () -> Void = {}) async throws -> (
        LoopSettingsModel, AppDatabase, FakeWearableSource
    ) {
        let database = try AppDatabase.inMemory()
        let clock = FixedClock(now: now, timeZone: .gmt)
        let band = try FakeWearableSource(scenario: .normal, failure: failure)
        let bandSync = BandSync(band: band, database: database, clock: clock)
        let pipeline = SyncPipeline(bandSync: bandSync, database: database, clock: clock, status: SyncStatusStore(defaults: .throwaway()))
        try await database.save(BandInfo(deviceId: "FAKE0001", name: "Polar Loop", pairedAt: now.addingTimeInterval(-86_400)))
        let model = LoopSettingsModel(
            database: database, clock: clock, bandSync: bandSync, pipeline: pipeline, forget: nil, backupSetUpError: nil,
            runSync: { lastRead }, didForget: didForget, askHealth: nil
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

    @Test func theWristIsLeftUntilChosenThenSentToTheLoopAndStored() async throws {
        let (model, database, band) = try await settings()
        await model.load()
        #expect(model.wrist == .left)

        await model.chooseWrist(.right)

        #expect(model.wrist == .right)
        #expect(await band.wrist == .right)
        #expect(try await database.wrist() == .right)
    }

    @Test func aLoopThatRefusesTheWristStoresNothing() async throws {
        let (model, database, band) = try await settings(failure: .wristFailed)

        await model.chooseWrist(.right)

        #expect(model.wrist == .left)
        #expect(model.wristNotSaved)
        #expect(await band.wrist == nil)
        #expect(try await database.wrist() == .left)
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

    func healthLines(on: Bool, _ run: HealthRun?) -> [String] {
        LoopSettingsModel.healthLines(HealthStatus(isOn: on, lastRun: run), now: now)
    }

    func run(_ outcome: HealthRun.Outcome = .written, daysToGo: Int = 0, notAllowed: [HealthKind] = [], wroteAny: Bool = true) -> HealthRun {
        HealthRun(at: now.addingTimeInterval(-9 * 60), outcome: outcome, daysToGo: daysToGo, notAllowed: notAllowed, wroteAny: wroteAny)
    }

    @Test func theAppleHealthLineSaysHowTheLastWriteWent() {
        #expect(
            healthLines(on: false, nil) == [
                "Copies your readings into Apple Health on this iPhone, so apps you allow there can read them. Vesel never reads from Health."
            ])
        #expect(healthLines(on: true, run(daysToGo: 42)) == ["Writing to Apple Health · 42 days to go"])
        #expect(healthLines(on: true, run(.waitingForUnlock, daysToGo: 1)) == ["Writing to Apple Health · 1 day to go"])
        #expect(healthLines(on: true, run()) == ["Up to date · written 9 minutes ago"])
        #expect(healthLines(on: true, run(wroteAny: false)) == ["Nothing to write yet. Vesel writes after its first read of your Loop."])
        #expect(
            healthLines(on: true, run(notAllowed: [.sleep, .steps])) == [
                "Up to date · written 9 minutes ago",
                "Not allowed in Health: Sleep, Steps. Allow them in Health › your profile › Apps › Vesel.",
            ])
        #expect(
            healthLines(on: true, run(notAllowed: HealthKind.allCases)) == [
                "Health isn't letting Vesel write anything. Allow it in Health › your profile › Apps › Vesel."
            ])
        #expect(healthLines(on: true, run(.failed)) == ["Couldn't write to Apple Health. Vesel tries again at its next read."])
        #expect(
            healthLines(on: false, run()) == [
                "What Vesel wrote stays in Apple Health. To remove it: Health › your profile › Apps › Vesel › Delete All Data."
            ])
    }

    /// Turning it on shows Apple's sheet and the switch reads back on; turning it off keeps it off.
    @Test func theHealthSwitchIsStoredAndAsksOnTurningOn() async throws {
        let database = try AppDatabase.inMemory()
        let clock = FixedClock(now: now, timeZone: .gmt)
        let bandSync = BandSync(band: try FakeWearableSource(scenario: .normal), database: database, clock: clock)
        let pipeline = SyncPipeline(bandSync: bandSync, database: database, clock: clock, status: SyncStatusStore(defaults: .throwaway()))
        let asked = Counter()
        let model = LoopSettingsModel(
            database: database, clock: clock, bandSync: bandSync, pipeline: pipeline, forget: nil, backupSetUpError: nil,
            runSync: { nil }, didForget: {}, askHealth: { asked.add() }
        )

        await model.setHealthWrite(true)
        await observe(model.observeHealth) { model.health?.isOn == true }

        #expect(asked.count == 1)
        #expect(model.healthLines == ["Writing to Apple Health"])

        await model.setHealthWrite(false)
        #expect(try await database.healthStatus().isOn == false)
        #expect(asked.count == 1)
    }
}

@MainActor
final class Counter {
    private(set) var count = 0
    func add() { count += 1 }
}
