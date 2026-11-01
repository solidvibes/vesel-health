import Foundation
import Testing
import VeselCore
@testable import VeselStorage

struct SyncRunObservationTests {
    func log(_ database: AppDatabase, limit: Int = 20) async throws -> SyncLog {
        for try await value in database.observeSyncRuns(limit: limit) { return value }
        throw CancellationError()
    }

    func run(_ database: AppDatabase, _ start: String, _ outcome: SyncOutcome?, finish: String? = nil) async throws {
        let id = try await database.startSyncRun(.manual, at: at(start))
        if let outcome { try await database.finishSyncRun(id, outcome: outcome, detail: nil, at: at(finish ?? start)) }
    }

    @Test func neverReadHasNoRunsAndNoLastRead() async throws {
        let found = try await log(try AppDatabase.inMemory())
        #expect(found == SyncLog(runs: [], lastRead: nil, triesSinceLastRead: 0))
    }

    @Test func runsComeNewestFirstAndStopAtTheLimit() async throws {
        let database = try AppDatabase.inMemory()
        for hour in 1...5 { try await run(database, "2026-10-26T0\(hour):00:00Z", .success) }
        let found = try await log(database, limit: 3)
        #expect(found.runs.map(\.startedAt) == [at("2026-10-26T05:00:00Z"), at("2026-10-26T04:00:00Z"), at("2026-10-26T03:00:00Z")])
    }

    @Test func triesAreTheFinishedRunsSinceTheLastSuccess() async throws {
        let database = try AppDatabase.inMemory()
        try await run(database, "2026-10-26T06:00:00Z", .failed)
        try await run(database, "2026-10-26T07:00:00Z", .success, finish: "2026-10-26T07:01:00Z")
        try await run(database, "2026-10-26T08:00:00Z", .unreachable)
        try await run(database, "2026-10-26T09:00:00Z", .failed)
        try await run(database, "2026-10-26T10:00:00Z", .unreachable)
        let found = try await log(database)
        #expect(found.lastRead == at("2026-10-26T07:01:00Z"))
        #expect(found.triesSinceLastRead == 3)

        try await run(database, "2026-10-26T11:00:00Z", .success)
        #expect(try await log(database).triesSinceLastRead == 0)
    }

    @Test func aRunThatNeverFinishedIsNotATry() async throws {
        let database = try AppDatabase.inMemory()
        try await run(database, "2026-10-26T07:00:00Z", .success, finish: "2026-10-26T07:01:00Z")
        try await run(database, "2026-10-26T08:00:00Z", .unreachable)
        try await run(database, "2026-10-26T09:00:00Z", nil)
        let found = try await log(database)
        #expect(found.triesSinceLastRead == 1)
        #expect(found.runs.first?.outcome == nil)
    }

    @Test func neverReadCountsEveryFinishedRun() async throws {
        let database = try AppDatabase.inMemory()
        try await run(database, "2026-10-26T08:00:00Z", .unreachable)
        try await run(database, "2026-10-26T09:00:00Z", .unreachable)
        try await run(database, "2026-10-26T10:00:00Z", nil)
        let found = try await log(database)
        #expect(found.lastRead == nil)
        #expect(found.triesSinceLastRead == 2)
    }
}
