import Foundation
import Observation
import UserNotifications
import VeselCore
import VeselStorage
import VeselSync
import VeselWearable

enum ForgetStep: Equatable {
    case confirm
    case finalSync
    /// The final sync didn't finish: anything since `lastRead` would be lost.
    case lost(lastRead: Date?)
    case resetting
    /// `bandWasReset` is false when the Loop couldn't be reached and must be reset by hand.
    case done(bandWasReset: Bool)
}

@MainActor
@Observable
final class LoopSettingsModel {
    /// Above this share of used band storage, Loop & settings warns.
    static let storageWarningShare = 0.6

    private(set) var band: BandInfo?
    private(set) var connection: ConnectionState = .disconnected
    private(set) var lastRead: Date?
    private(set) var alerts = AlertSettings()
    /// The Loop's training detection as last written; nil before the one-time switch-on.
    private(set) var workoutDetection: WorkoutDetection?
    /// The owner said no to notifications in iOS: the switches can't reach them.
    private(set) var notificationsDenied = false
    var forget: ForgetStep?
    /// Nil until read.
    private(set) var backupIsSetUp: Bool?
    private(set) var backup: BackupRecord?
    private(set) var backupWaiting = 0
    private(set) var backingUp = false
    private(set) var settingUpBackup = false
    private(set) var backupSetUpError: Backup.SetUpError?
    var scanningBackupQR = false
    private let database: AppDatabase
    private let clock: any VeselClock
    private let bandSync: BandSync
    private let pipeline: SyncPipeline
    private let runSync: () async -> SyncOutcome?
    private let didForget: () -> Void

    init(
        database: AppDatabase,
        clock: any VeselClock,
        bandSync: BandSync,
        pipeline: SyncPipeline,
        forget: ForgetStep?,
        backupSetUpError: Backup.SetUpError?,
        runSync: @escaping () async -> SyncOutcome?,
        didForget: @escaping () -> Void
    ) {
        self.database = database
        self.clock = clock
        self.bandSync = bandSync
        self.pipeline = pipeline
        self.runSync = runSync
        self.didForget = didForget
        self.forget = forget
        self.backupSetUpError = backupSetUpError
    }

    var storageUsedShare: Double? {
        guard let band, let free = band.diskFreeBytes, let total = band.diskTotalBytes, total > 0 else { return nil }
        return Double(total - free) / Double(total)
    }

    var storageIsHigh: Bool { (storageUsedShare ?? 0) > Self.storageWarningShare }

    /// Shows what's stored now, then again once a running sync has finished.
    func load() async {
        await read()
        await pipeline.idle()
        await read()
    }

    private func read() async {
        band = try? await database.band()
        lastRead = try? await database.lastSuccessfulSync()
        connection = await bandSync.connectionState()
        alerts = (try? await database.alertSettings()) ?? AlertSettings()
        workoutDetection = try? await database.workoutDetection()
        notificationsDenied = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
        if case .lost(nil) = forget { forget = .lost(lastRead: lastRead) }
        await readBackup()
    }

    private func readBackup() async {
        backupIsSetUp = await Backup.isSetUp(database: database)
        backup = try? await BackupRecord.load(from: database)
        backupWaiting = (try? await database.pendingUploadCount(now: clock.now)) ?? 0
    }

    /// A QR was scanned: set up, then back up right away.
    func setUpBackup(_ qr: String) async {
        scanningBackupQR = false
        settingUpBackup = true
        backupSetUpError = nil
        if case .failure(let error) = await Backup.setUp(qr, database: database, clock: clock) {
            backupSetUpError = error
        }
        settingUpBackup = false
        await readBackup()
        if backupSetUpError == nil { await backUpNow() }
    }

    func backUpNow() async {
        backingUp = true
        _ = await pipeline.backUpNow()
        backingUp = false
        await readBackup()
    }

    func removeBackup() async {
        await Backup.remove(database: database)
        backupSetUpError = nil
        await readBackup()
    }

    /// Turning one on asks for notifications, the first time. A switch that couldn't be saved flips back.
    func setAlert(_ kind: AlertKind, on: Bool) async {
        let was = alerts.values[kind]
        alerts.values[kind] = on
        do {
            try await database.setAlert(kind, on: on)
        } catch {
            alerts.values[kind] = was
            return
        }
        if on { await AlertNotifier.askPermissionOnce() }
        notificationsDenied = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    func confirmForget() async {
        forget = .finalSync
        let outcome = await runSync()
        if outcome == .success {
            await reset()
        } else {
            lastRead = try? await database.lastSuccessfulSync()
            forget = .lost(lastRead: lastRead)
        }
    }

    func reset() async {
        forget = .resetting
        let wasReset = (try? await bandSync.factoryReset()) != nil
        try? await database.forgetBand(at: clock.now)
        forget = .done(bandWasReset: wasReset)
    }

    func finishForgetting() {
        forget = nil
        didForget()
    }
}
