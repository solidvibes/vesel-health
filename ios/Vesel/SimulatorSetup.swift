#if DEBUG && targetEnvironment(simulator)
import Foundation
import VeselCore
import VeselStorage
import VeselSync
import VeselWearableTesting

/// The Simulator's start: the `pairing` scenario starts unpaired; the others start with a band paired on the fixtures'
/// first day. `-VeselBackupQR <text>` sets up the Mac mini backup as if that QR was scanned; `-VeselBackupQR remove`
/// removes it.
enum SimulatorSetup {
    /// What setting up the backup said, if it failed.
    static func prepare(database: AppDatabase, clock: any VeselClock) async -> Backup.SetUpError? {
        var backupError: Backup.SetUpError?
        switch UserDefaults.standard.string(forKey: "VeselBackupQR") {
        case "remove"?:
            await Backup.remove(database: database)
        case let qr?:
            if case .failure(let error) = await Backup.setUp(qr, database: database, clock: clock) { backupError = error }
        case nil:
            break
        }
        if FakeScenario() == .pairing {
            try? await database.forgetBand(at: clock.now)
        } else if (try? await database.band()) == nil {
            try? await database.save(BandInfo(deviceId: "FAKE0001", name: "Polar Loop", pairedAt: Date(timeIntervalSince1970: 1_790_409_600)))
            try? await database.save(Profile(birthYear: 1990, sex: .male, heightCm: 180, weightKg: 75, sleepGoalMinutes: 480))
        }
        return backupError
    }
}
#endif
