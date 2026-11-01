import Foundation
import GRDB

/// Row counts per table and the last time a row arrived, read straight from the server's backup file.
public struct BackupStats: Sendable, Equatable {
    public let counts: [String: Int]
    public let lastReceivedAt: Date?

    public init(counts: [String: Int], lastReceivedAt: Date?) {
        self.counts = counts
        self.lastReceivedAt = lastReceivedAt
    }

    public static let empty = BackupStats(counts: [:], lastReceivedAt: nil)

    public var isEmpty: Bool { counts.values.allSatisfy { $0 == 0 } }

    /// Never creates the file and never writes to it. SQLite's read-only open can't read a WAL file whose `-shm` is gone
    /// (the server's state between requests), so the connection is read-write with `query_only` on.
    public static func read(database: URL) throws -> BackupStats {
        guard FileManager.default.fileExists(atPath: database.path) else { return .empty }
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA query_only = 1")
        }
        let queue = try DatabaseQueue(path: database.path, configuration: configuration)
        defer { try? queue.close() }
        return try queue.read { db in
            guard try db.tableExists("row") else { return .empty }
            var counts: [String: Int] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT table_name, COUNT(*) AS n FROM row GROUP BY table_name") {
                counts[row["table_name"]] = row["n"]
            }
            let last = try String.fetchOne(db, sql: "SELECT MAX(received_at) FROM row")
            return BackupStats(counts: counts, lastReceivedAt: last.flatMap(parseReceivedAt))
        }
    }

    /// The server writes Python's `datetime.isoformat()` in UTC: `2026-10-26T07:42:00.123456+00:00`, no fraction when it is zero.
    static func parseReceivedAt(_ text: String) -> Date? {
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
            return date
        }
        return try? Date(text, strategy: Date.ISO8601FormatStyle())
    }
}
