import Foundation

/// The server's data folder, shared with the Terminal set-up: `~/Library/Application Support/vesel-server/`.
public struct ServerHome: Sendable, Equatable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static func standard(userHome: URL) -> ServerHome {
        ServerHome(root: userHome.appending(path: "Library/Application Support/vesel-server", directoryHint: .isDirectory))
    }

    public var certs: URL { root.appending(path: "certs", directoryHint: .isDirectory) }
    public var certificate: URL { certs.appending(path: "cert.pem") }
    public var privateKey: URL { certs.appending(path: "key.pem") }
    public var tokenHash: URL { root.appending(path: "token.sha256") }
    public var database: URL { root.appending(path: "vesel.sqlite") }
    public var log: URL { root.appending(path: "server.log") }
    public var pidFile: URL { root.appending(path: "server.pid") }
    public var venv: URL { root.appending(path: "venv", directoryHint: .isDirectory) }
    public var python: URL { venv.appending(path: "bin/python") }

    public var isPaired: Bool {
        [certificate, privateKey, tokenHash].allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Re-applies 700 to the folders and 600 to the files that exist.
    public func sweepPermissions() throws {
        let fileManager = FileManager.default
        for folder in [root, certs, venv] where fileManager.fileExists(atPath: folder.path) {
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        }
        let databaseFiles = ["vesel.sqlite", "vesel.sqlite-wal", "vesel.sqlite-shm"].map { root.appending(path: $0) }
        for file in [certificate, privateKey, tokenHash, log, pidFile] + databaseFiles where fileManager.fileExists(atPath: file.path) {
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
    }

    public func readPid() -> Int32? {
        guard let text = try? String(contentsOf: pidFile, encoding: .utf8) else { return nil }
        return Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public func writePid(_ pid: Int32) throws {
        try Data("\(pid)\n".utf8).write(to: pidFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: pidFile.path)
    }

    public func removePid() {
        try? FileManager.default.removeItem(at: pidFile)
    }
}
