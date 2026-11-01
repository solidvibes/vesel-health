import Foundation
import GRDB
import SQLite3

/// The phone's database: the source of truth for every screen, widget and alert.
/// The app is its only writer; widgets open it read-only (see GRDB's "Sharing a Database").
public final class AppDatabase: Sendable {
    /// Nil when the build's Info.plist has no `VeselAppGroup`.
    public static let appGroup = Bundle.main.object(forInfoDictionaryKey: "VeselAppGroup") as? String

    let writer: any DatabaseWriter

    init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
        if try writer.read(Self.migrator.hasBeenSuperseded) {
            throw StorageError.newerSchema
        }
    }

    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue(configuration: configuration()))
    }

    #if os(iOS)
    public static func shared() throws -> AppDatabase {
        guard let appGroup, let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            throw StorageError.noAppGroup
        }
        return try open(in: container.appending(path: "Library/Application Support/Vesel", directoryHint: .isDirectory))
    }
    #endif

    /// Opens (or creates) `vesel.sqlite` in `directory`. The directory is excluded from device backups,
    /// so the database and its `-wal` and `-shm` files never go to iCloud.
    static func open(in directory: URL) throws -> AppDatabase {
        try prepare(directory: directory)
        let url = directory.appending(path: "vesel.sqlite")
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinatorError: NSError?
        var result: Result<AppDatabase, any Error>?
        coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &coordinatorError) { url in
            result = Result {
                var configuration = configuration()
                configuration.prepareDatabase { db in
                    if !db.configuration.readonly {
                        var flag: CInt = 1
                        let code = withUnsafeMutablePointer(to: &flag) { flag in
                            sqlite3_file_control(db.sqliteConnection, nil, SQLITE_FCNTL_PERSIST_WAL, flag)
                        }
                        guard code == SQLITE_OK else {
                            throw DatabaseError(resultCode: ResultCode(rawValue: code))
                        }
                    }
                }
                return try AppDatabase(DatabasePool(path: url.path, configuration: configuration))
            }
        }
        if let coordinatorError { throw coordinatorError }
        guard let result else { throw StorageError.notOpened }
        return try result.get()
    }

    static func prepare(directory: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: directory.path
        )
        #endif
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directory = directory
        try directory.setResourceValues(values)
    }

    private static func configuration() -> Configuration {
        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        configuration.observesSuspensionNotifications = true
        return configuration
    }

    /// Call before the app may be suspended, so iOS never kills it for holding the database lock (0xdead10cc).
    public func suspend() {
        NotificationCenter.default.post(name: Database.suspendNotification, object: nil)
    }

    public func resume() {
        NotificationCenter.default.post(name: Database.resumeNotification, object: nil)
    }

    /// True when an error only means the database is paused (`suspend()`): GRDB interrupts a running statement
    /// (`SQLITE_INTERRUPT`) and refuses new writes with `SQLITE_ABORT` and its own message. Any other abort is a real problem.
    public static func isPaused(_ error: any Error) -> Bool {
        guard let error = error as? DatabaseError else { return false }
        switch error.resultCode {
        case .SQLITE_INTERRUPT: return true
        case .SQLITE_ABORT: return error.message == "Database is suspended"
        default: return false
        }
    }
}

public enum StorageError: Error {
    case newerSchema
    /// The build has no App Group, or its entitlements don't grant it.
    case noAppGroup
    /// The file coordinator returned without running the open.
    case notOpened
    /// A stored day isn't a `yyyy-MM-dd` date.
    case badDay
}
