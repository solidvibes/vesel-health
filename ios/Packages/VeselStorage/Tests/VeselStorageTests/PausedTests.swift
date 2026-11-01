import Foundation
@testable import GRDB
import Testing
@testable import VeselStorage

/// A paused database is not a read problem: screens wait for the next start instead of saying something went wrong.
struct PausedTests {
    /// Pauses only this database: `suspend()` posts to every open database in the process, and the other tests run beside this one.
    @Test func aWriteToAPausedDatabaseIsPaused() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "vesel-\(UUID().uuidString)/Vesel")
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let database = try AppDatabase.open(in: directory)
        let pool = try #require(database.writer as? DatabasePool)

        pool.suspend()
        defer { pool.resume() }
        let error = #expect(throws: DatabaseError.self) {
            try pool.write { try $0.execute(sql: "INSERT INTO setting (key, value) VALUES ('paused', 'yes')") }
        }
        #expect(error.map(AppDatabase.isPaused) == true)
        // WAL lets reads through while paused.
        #expect(try pool.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM setting") } != nil)
    }

    @Test func anInterruptedStatementIsPaused() {
        #expect(AppDatabase.isPaused(DatabaseError(resultCode: .SQLITE_INTERRUPT)))
    }

    @Test func otherErrorsAreProblems() {
        #expect(!AppDatabase.isPaused(DatabaseError(resultCode: .SQLITE_ABORT)))
        #expect(!AppDatabase.isPaused(DatabaseError(resultCode: .SQLITE_CONSTRAINT)))
        #expect(!AppDatabase.isPaused(StorageError.notOpened))
        #expect(!AppDatabase.isPaused(CancellationError()))
    }
}
