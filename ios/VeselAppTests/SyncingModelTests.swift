import Foundation
import Testing
import VeselCore
import VeselStorage
@testable import Vesel

/// The Syncing page's words. "Reading now…" is known only from the app's live sync state.
@MainActor
struct SyncingModelTests {
    let now = try! Date("2026-10-26T09:00:00Z", strategy: .iso8601)

    func model(status: SyncStatusStore = SyncStatusStore(defaults: .throwaway())) throws -> (SyncingModel, AppDatabase) {
        let database = try AppDatabase.inMemory()
        let clock = FixedClock(now: now, timeZone: .gmt)
        return (SyncingModel(database: database, status: status, clock: clock, runSync: { .success }), database)
    }

    func start(_ database: AppDatabase, _ trigger: SyncTrigger, _ iso: String) async throws -> Int64 {
        try await database.startSyncRun(trigger, at: try Date(iso, strategy: .iso8601))
    }

    func load(_ model: SyncingModel) async {
        let task = Task { await model.observe() }
        await waitUntil { model.log != nil }
        task.cancel()
        await task.value
    }

    @Test func theNewestRowReadsNowOnlyWhileTheAppReads() async throws {
        let status = SyncStatusStore(defaults: .throwaway())
        let (model, database) = try model(status: status)
        _ = try await start(database, .manual, "2026-10-26T08:55:00Z")
        await load(model)
        #expect(model.rows.map(\.outcome) == ["didn't finish"])
        #expect(model.rows.first?.mark == .problem)

        status.set(.reading(SyncProgress()))
        #expect(model.rows.map(\.outcome) == ["reading now…"])
        #expect(model.rows.first?.mark == .running)
    }

    @Test func onlyTheNewestRowCanBeReading() async throws {
        let status = SyncStatusStore(defaults: .throwaway())
        let (model, database) = try model(status: status)
        _ = try await start(database, .launch, "2026-10-26T07:00:00Z")
        _ = try await start(database, .manual, "2026-10-26T08:55:00Z")
        status.set(.reading(SyncProgress()))
        await load(model)
        #expect(model.rows.map(\.outcome) == ["reading now…", "didn't finish"])
    }

    @Test func aFinishedNewestRowKeepsItsEndingWhileTheAppStillReads() async throws {
        let status = SyncStatusStore(defaults: .throwaway())
        let (model, database) = try model(status: status)
        let id = try await start(database, .manual, "2026-10-26T08:55:00Z")
        try await database.finishSyncRun(id, outcome: .success, detail: nil, at: try Date("2026-10-26T08:56:00Z", strategy: .iso8601))
        status.set(.reading(SyncProgress()))
        await load(model)
        #expect(model.rows.map(\.outcome) == ["done"])
        #expect(model.rows.first?.mark == .done)
    }

    @Test func lastReadSaysHowLongAgo() async throws {
        let (model, database) = try model()
        let id = try await start(database, .manual, "2026-10-26T00:00:00Z")
        try await database.finishSyncRun(id, outcome: .success, detail: nil, at: try Date("2026-10-26T00:00:00Z", strategy: .iso8601))
        await load(model)
        #expect(model.title == "Last read 9 hours ago")
        #expect(Formatters.ago(now.addingTimeInterval(-30), now: now) == "just now")
    }

    @Test func rowsGroupUnderTodayYesterdayAndTheDate() async throws {
        let (model, database) = try model()
        for (trigger, iso) in [
            (SyncTrigger.launch, "2026-10-24T20:00:00Z"), (.bandEvent, "2026-10-25T21:00:00Z"), (.imUp, "2026-10-26T06:00:00Z"),
            (.manual, "2026-10-26T08:00:00Z"),
        ] {
            let id = try await start(database, trigger, iso)
            try await database.finishSyncRun(id, outcome: .success, detail: nil, at: try Date(iso, strategy: .iso8601))
        }
        await load(model)
        let saturday = Formatters.day(DayKey(try Date("2026-10-24T20:00:00Z", strategy: .iso8601), in: .gmt), zone: .gmt)
        #expect(model.groups.map(\.title) == ["Today", "Yesterday", saturday])
        #expect(model.groups.first?.rows.map(\.trigger) == ["Sync now", "I'm up"])
    }

    @Test func troubleNamesTheLastReadAndTheTries() async throws {
        let (model, database) = try model()
        let ok = try await start(database, .manual, "2026-10-26T07:00:00Z")
        try await database.finishSyncRun(ok, outcome: .success, detail: nil, at: try Date("2026-10-26T07:01:00Z", strategy: .iso8601))
        for hour in ["08", "09"] {
            let id = try await start(database, .backgroundRefresh, "2026-10-26T\(hour):00:00Z")
            try await database.finishSyncRun(
                id, outcome: .unreachable, detail: SyncDetail.notNearby, at: try Date("2026-10-26T\(hour):00:05Z", strategy: .iso8601))
        }
        await load(model)
        #expect(
            model.trouble
                == "Vesel hasn't reached your Loop since \(Formatters.time(try Date("2026-10-26T07:01:00Z", strategy: .iso8601), zone: .gmt)). It tried 2 times."
        )
    }

    @Test func neverReadSaysSo() async throws {
        let (model, database) = try model()
        let id = try await start(database, .launch, "2026-10-26T08:00:00Z")
        try await database.finishSyncRun(id, outcome: .unreachable, detail: SyncDetail.notNearby, at: try Date("2026-10-26T08:00:05Z", strategy: .iso8601))
        await load(model)
        #expect(model.title == "Not read yet")
        #expect(model.trouble == "Vesel hasn't read your Loop yet.")
    }
}
