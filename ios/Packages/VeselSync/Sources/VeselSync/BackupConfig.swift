import Foundation
import VeselStorage

/// Where the Mac mini is and which certificate key it must show. Kept in the `setting` table; the token is in the Keychain.
public struct BackupConfig: Sendable, Equatable {
    public var host: String
    public var port: Int
    /// Standard base64 of the SHA-256 of the certificate's SubjectPublicKeyInfo.
    public var pin: String

    public init(host: String, port: Int, pin: String) {
        self.host = host
        self.port = port
        self.pin = pin
    }

    /// Reads the set-up QR: `vesel-backup://<host>.local:<port>?token=<base64url>&pin=<base64, percent-encoded>`.
    /// Only a `.local` name on the home network (or `localhost`, for the Simulator test) is taken.
    public static func parse(_ text: String) -> (config: BackupConfig, token: String)? {
        guard let components = URLComponents(string: text), components.scheme == "vesel-backup",
            let host = components.host, isHomeNetwork(host), let port = components.port, (1...65535).contains(port),
            let items = components.queryItems,
            let token = items.first(where: { $0.name == "token" })?.value, isToken(token),
            let pin = items.first(where: { $0.name == "pin" })?.value, Data(base64Encoded: pin)?.count == 32
        else { return nil }
        return (BackupConfig(host: host, port: port, pin: pin), token)
    }

    private static func isHomeNetwork(_ host: String) -> Bool {
        let host = host.lowercased()
        return host == "localhost" || (host.hasSuffix(".local") && host.count > ".local".count)
    }

    private static func isToken(_ token: String) -> Bool {
        token.count == 43 && token.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    var baseURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.port = port
        return components.url!
    }

    static let hostKey = "backup.host"
    static let portKey = "backup.port"
    static let pinKey = "backup.pin"

    public static func load(from database: AppDatabase) async throws -> BackupConfig? {
        guard let host = try await database.setting(hostKey),
            let port = try await database.setting(portKey).flatMap(Int.init),
            let pin = try await database.setting(pinKey)
        else { return nil }
        return BackupConfig(host: host, port: port, pin: pin)
    }

    public func save(to database: AppDatabase) async throws {
        try await database.setSettings([Self.hostKey: host, Self.portKey: String(port), Self.pinKey: pin])
    }

    /// Forgets the Mac mini and what the last backup did. The Mac mini's copy stays.
    public static func remove(from database: AppDatabase) async throws {
        try await database.setSettings([
            hostKey: nil, portKey: nil, pinKey: nil,
            BackupRecord.lastBackupKey: nil, BackupRecord.outcomeKey: nil, BackupRecord.attemptKey: nil,
        ])
    }
}

/// How the last backup went, for Loop & settings. Kept apart from `sync_run`: that one is about the band.
public enum BackupOutcome: String, Sendable, Equatable {
    /// Everything waiting reached the Mac mini.
    case backedUp = "backed_up"
    /// No answer within 5 seconds: away from home, or the Mac mini is off.
    case away
    /// The Mac mini turned the key down (set up again on the Mac mini): scan the QR again.
    case unauthorized
    /// Something answered with another certificate: scan the QR again.
    case wrongCertificate = "wrong_certificate"
    /// The Mac mini answered but didn't take everything; the rest waits for the next sync.
    case failed
    /// The Mac mini speaks another upload format.
    case otherFormat = "other_format"

    public var needsNewQR: Bool { self == .unauthorized || self == .wrongCertificate }
}

public struct BackupRecord: Sendable, Equatable {
    /// When everything waiting last reached the Mac mini.
    public var lastBackup: Date?
    public var lastOutcome: BackupOutcome?

    static let lastBackupKey = "backup.last_backup_at"
    static let outcomeKey = "backup.last_outcome"
    static let attemptKey = "backup.last_attempt_at"

    public static func load(from database: AppDatabase) async throws -> BackupRecord {
        let last = try await database.setting(lastBackupKey).flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
        let outcome = try await database.setting(outcomeKey).flatMap(BackupOutcome.init(rawValue:))
        return BackupRecord(lastBackup: last, lastOutcome: outcome)
    }

    static func save(_ outcome: BackupOutcome, at date: Date, to database: AppDatabase) async throws {
        var values: [String: String?] = [outcomeKey: outcome.rawValue, attemptKey: String(date.timeIntervalSince1970.rounded(.down))]
        if outcome == .backedUp { values[lastBackupKey] = String(date.timeIntervalSince1970.rounded(.down)) }
        try await database.setSettings(values)
    }
}
