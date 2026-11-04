import Foundation
import Testing
import VeselCore
import VeselStorage
import VeselWearable
import VeselWearableTesting
@testable import Vesel

/// Pairing on the fake band: the profile goes to the band first, then the phone; a band that refuses it leaves nothing stored.
@MainActor
struct PairingModelTests {
    let now = try! Date("2026-10-26T09:00:00Z", strategy: .iso8601)

    func pairing(failure: FakeFailure? = nil, didPair: @escaping () -> Void) throws -> (PairingModel, AppDatabase) {
        let database = try AppDatabase.inMemory()
        let clock = FixedClock(now: now, timeZone: .gmt)
        let bandSync = BandSync(band: try FakeWearableSource(scenario: .pairing, failure: failure), database: database, clock: clock)
        let model = PairingModel(bandSync: bandSync, database: database, clock: clock, units: UnitsStore(), launchStep: .before, didPair: didPair)
        return (model, database)
    }

    func fillIn(_ model: PairingModel) {
        model.draft.birthYear = "1990"
        model.draft.height = "180"
        model.draft.weight = "78"
        model.draft.sex = .male
    }

    @Test func pairingStoresTheProfileAndTheBand() async throws {
        var paired = false
        let (model, database) = try pairing { paired = true }
        model.startLooking()
        await waitUntil { model.step == .aboutYou }
        #expect(model.step == .aboutYou)

        fillIn(model)
        model.finish()
        await waitUntil { paired }

        #expect(paired)
        #expect(try await database.profile() == Profile(birthYear: 1990, sex: .male, heightCm: 180, weightKg: 78, sleepGoalMinutes: 480))
        #expect(try await database.band()?.deviceId == "FAKE0001")
    }

    @Test func pairingAgainSendsTheStoredWristToTheBand() async throws {
        var paired = false
        let database = try AppDatabase.inMemory()
        let clock = FixedClock(now: now, timeZone: .gmt)
        let band = try FakeWearableSource(scenario: .pairing)
        let bandSync = BandSync(band: band, database: database, clock: clock)
        try await database.setWrist(.right)
        let model = PairingModel(bandSync: bandSync, database: database, clock: clock, units: UnitsStore(), launchStep: .before, didPair: { paired = true })
        model.startLooking()
        await waitUntil { model.step == .aboutYou }
        fillIn(model)
        model.finish()
        await waitUntil { paired }

        #expect(await band.wrist == .right)
        #expect(await band.calls.firstIndex(of: "firstTimeUse")! < band.calls.firstIndex(of: "setWrist")!)
    }

    @Test func aBandThatRefusesTheProfileLeavesNothingStored() async throws {
        var paired = false
        let (model, database) = try pairing(failure: .setupFailed) { paired = true }
        model.startLooking()
        await waitUntil { model.step == .aboutYou }

        fillIn(model)
        model.finish()
        await waitUntil { model.setupFailed }

        #expect(model.setupFailed)
        #expect(!paired)
        #expect(try await database.profile() == nil)
        #expect(try await database.band() == nil)
    }
}
