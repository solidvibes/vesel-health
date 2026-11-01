import Foundation
import VeselCore
import VeselStorage

/// The Mac mini backup as the app uses it: set up from the QR, run after a sync, remove.
public enum Backup {
    public enum SetUpError: Error, Equatable {
        case notABackupQR
        case unreachable(BackupOutcome)
        case keychain
    }

    /// Reads the QR, checks the Mac mini answers on its pin and takes the token, then keeps both. A Mac mini with
    /// another certificate than before (a new one, or `setup.sh --force`; Vesel Backup's Pair again keeps it) gets everything again; resending is harmless.
    public static func setUp(_ qr: String, database: AppDatabase, clock: any VeselClock) async -> Result<Void, SetUpError> {
        guard let (config, token) = BackupConfig.parse(qr) else { return .failure(.notABackupQR) }
        let uploader = Uploader(config: config, token: token, database: database, transport: PinnedSession(pin: config.pin), clock: clock)
        if let failure = await uploader.check() { return .failure(.unreachable(failure)) }
        do {
            let previous = try await BackupConfig.load(from: database)
            try BackupToken.save(token)
            if previous?.pin != config.pin { try await database.clearUploadMarks() }
            try await BackupConfig.remove(from: database)
            try await config.save(to: database)
            return .success(())
        } catch {
            BackupToken.delete()
            return .failure(.keychain)
        }
    }

    /// Nil when backup isn't set up.
    public static func run(database: AppDatabase, clock: any VeselClock) async -> BackupOutcome? {
        guard let config = try? await BackupConfig.load(from: database), let token = BackupToken.read() else { return nil }
        return await Uploader(config: config, token: token, database: database, transport: PinnedSession(pin: config.pin), clock: clock).run()
    }

    public static func isSetUp(database: AppDatabase) async -> Bool {
        (try? await BackupConfig.load(from: database)) != nil && BackupToken.read() != nil
    }

    /// Forgets the Mac mini on this phone. The copy on the Mac mini stays.
    public static func remove(database: AppDatabase) async {
        BackupToken.delete()
        try? await BackupConfig.remove(from: database)
    }
}
