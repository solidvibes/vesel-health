import Foundation
import GRDB
import Testing
@testable import VeselBackupKit

struct BackupStatsTests {
    /// The server's table, as `vesel_server/storage.py` makes it. The server's Python SQLite removes `-wal`/`-shm` on close;
    /// macOS's keeps them, so they are removed here to match.
    func makeServerDatabase(at url: URL, rows: [(table: String, key: String, receivedAt: String)]) throws {
        var sql = """
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS row (
             table_name TEXT NOT NULL, row_key TEXT NOT NULL, json TEXT NOT NULL, received_at TEXT NOT NULL,
             PRIMARY KEY (table_name, row_key));
            """
        for row in rows {
            sql += "INSERT INTO row VALUES ('\(row.table)', '\(row.key)', '{}', '\(row.receivedAt)');\n"
        }
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/sqlite3")
        process.arguments = [url.path, sql]
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        try? FileManager.default.removeItem(atPath: url.path + "-wal")
        try? FileManager.default.removeItem(atPath: url.path + "-shm")
    }

    @Test func countsPerTableAndTheLastTime() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = folder.appending(path: "vesel.sqlite")
        try makeServerDatabase(
            at: database,
            rows: [
                ("sleep_night", "2026-10-25", "2026-10-26T07:00:00+00:00"),
                ("sleep_night", "2026-10-26", "2026-10-26T07:42:10.250000+00:00"),
                ("hr_sample", "1", "2026-10-26T07:41:00.000001+00:00"),
                ("profile", "me", "2026-10-25T21:00:00+00:00"),
            ])
        let stats = try BackupStats.read(database: database)
        #expect(stats.counts == ["sleep_night": 2, "hr_sample": 1, "profile": 1])
        let expected = try #require(BackupStats.parseReceivedAt("2026-10-26T07:42:10.250000+00:00"))
        #expect(stats.lastReceivedAt == expected)
        #expect(try DatabaseQueue(path: database.path).read { try String.fetchOne($0, sql: "PRAGMA journal_mode") } == "wal")
    }

    @Test func readsWhileTheServerHasItOpen() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = folder.appending(path: "vesel.sqlite")
        try makeServerDatabase(at: database, rows: [("alert_event", "a", "2026-10-26T07:00:00+00:00")])
        let writer = try DatabaseQueue(path: database.path)
        try writer.write { db in
            try db.execute(sql: "INSERT INTO row VALUES ('alert_event', 'b', '{}', '2026-10-26T08:00:00+00:00')")
        }
        #expect(try BackupStats.read(database: database).counts == ["alert_event": 2])
        try writer.close()
    }

    @Test func parsesBothServerTimeShapes() throws {
        let plain = try #require(BackupStats.parseReceivedAt("2026-10-26T07:00:00+00:00"))
        let fraction = try #require(BackupStats.parseReceivedAt("2026-10-26T07:00:00.500000+00:00"))
        #expect(fraction.timeIntervalSince(plain) == 0.5)
    }

    @Test func aMissingFileIsNothingYet() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = folder.appending(path: "vesel.sqlite")
        let stats = try BackupStats.read(database: database)
        #expect(stats == .empty)
        #expect(stats.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: database.path))
    }

    @Test func anEmptyTableIsNothingYet() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = folder.appending(path: "vesel.sqlite")
        try makeServerDatabase(at: database, rows: [])
        let stats = try BackupStats.read(database: database)
        #expect(stats.isEmpty)
        #expect(stats.lastReceivedAt == nil)
    }
}
