import Foundation
import GRDB
import Testing
import VeselCore
@testable import VeselStorage

struct WidgetSnapshotTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "vesel-\(UUID().uuidString)/Vesel")
    let berlin = TimeZone(identifier: "Europe/Berlin")!
    let today = DayKey(year: 2026, month: 10, day: 9)

    /// Eight nights, 2026-10-01 to 2026-10-08, worked out, and one successful sync at 06:00 UTC on the 9th.
    func seededDatabase() async throws -> AppDatabase {
        let database = try AppDatabase.open(in: directory)
        try await database.save(Profile(birthYear: 1990, sex: .male, heightCm: 180, weightKg: 75, sleepGoalMinutes: 480))
        for (index, hrv) in [30, 34, 38, 42, 46, 50, 54, 26].enumerated() {
            try await store(database, night: DayKey(year: 2026, month: 10, day: index + 1), hrv: hrv)
        }
        try await MetricsUpdater(database: database, clock: FixedClock(now: at("2026-10-09T06:00:00Z"), timeZone: berlin)).updateAfterSync()
        let run = try await database.startSyncRun(.manual, at: at("2026-10-09T05:59:00Z"))
        try await database.finishSyncRun(run, outcome: .success, detail: nil, at: at("2026-10-09T06:00:00Z"))
        return database
    }

    func store(_ database: AppDatabase, night: DayKey, hrv: Int) async throws {
        let end = night.start(in: TimeZone(identifier: "UTC")!).addingTimeInterval(5.5 * 3600)
        try await database.save(
            SleepNight(
                night: night, start: end.addingTimeInterval(-8 * 3600), end: end, goalMinutes: 480, phases: [SleepPhase(secondsFromStart: 0, state: .light)]),
            rawJSON: "{}"
        )
        try await database.save(
            NightlyRecharge(
                night: night, recoveryIndicator: 4, recoveryIndicatorSubLevel: 50,
                meanNightlyRecoveryRRI: 1000, meanNightlyRecoveryRMSSD: hrv, meanNightlyRecoveryRespirationInterval: 4000
            ),
            rawJSON: "{}"
        )
    }

    @Test func readsEverythingAWidgetShowsInOneRead() async throws {
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        _ = try await seededDatabase()

        let snapshot = try AppDatabase.readSnapshot(in: directory, today: today)

        #expect(snapshot.night == DayKey(year: 2026, month: 10, day: 8))
        #expect(snapshot.status?.indicator == 4)
        #expect(snapshot.status?.subLevel == 50)
        #expect(snapshot.asleepMinutes == 480)
        #expect(snapshot.lines.recovery.state == .inside)
        #expect(snapshot.lines.sleep.state == .inside)
        #expect(snapshot.lines.calm.state == .none)
        #expect(snapshot.earlierNights == 7)
        #expect(snapshot.headline?.sentence == "Things look good today.")
        #expect(snapshot.headline?.why == "Recovery is OK, and your sleep was right in your normal.")
        #expect(snapshot.syncedAt == at("2026-10-09T06:00:00Z"))
        #expect(snapshot.content == .ready)
        #expect(snapshot.stress(at: at("2026-10-09T08:00:00Z")).ringText == "Learning")
    }

    @Test func readsTheUnitsSettingMetricWithoutOne() async throws {
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let database = try await seededDatabase()
        #expect(try AppDatabase.readSnapshot(in: directory, today: today).units == .metric)

        try await database.setUnits(.us)
        #expect(try AppDatabase.readSnapshot(in: directory, today: today).units == .us)
        var observed = database.observeUnits().makeAsyncIterator()
        #expect(try await observed.next() == .us)
    }

    @Test func readsWhileTheAppHoldsAWriteTransaction() async throws {
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let database = try await seededDatabase()

        let during = try await database.writer.write { db in
            try db.execute(sql: "UPDATE nightly_recharge SET recovery_indicator = 1 WHERE night = '2026-10-08'")
            try db.execute(sql: "DELETE FROM computed_metric")
            return try AppDatabase.readSnapshot(in: directory, today: today)
        }

        #expect(during.status?.indicator == 4)
        #expect(during.asleepMinutes == 480)
        let after = try AppDatabase.readSnapshot(in: directory, today: today)
        #expect(after.asleepMinutes == nil)
    }

    @Test func aMissingFileMeansNoDataAndCreatesNothing() throws {
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

        let snapshot = try AppDatabase.readSnapshot(in: directory, today: today)

        #expect(snapshot == .empty)
        #expect(snapshot.content == .noData)
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "vesel.sqlite").path))
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func neverMigratesADatabaseTheAppHasNotBroughtUpToDate() async throws {
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appending(path: "vesel.sqlite").path
        do {
            let queue = try DatabaseQueue(path: path)
            try AppDatabase.migrator.migrate(queue, upTo: "v1")
        }

        let snapshot = try AppDatabase.readSnapshot(in: directory, today: today)

        #expect(snapshot == .empty)
        let queue = try DatabaseQueue(path: path)
        let applied = try await queue.read { try AppDatabase.migrator.appliedIdentifiers($0) }
        let tables = try await queue.read { try String.fetchAll($0, sql: "SELECT name FROM sqlite_master WHERE name = 'alert_event'") }
        #expect(applied == ["v1"])
        #expect(tables.isEmpty)
    }

    @Test func aDatabaseWithANewerSchemaMeansNoData() async throws {
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let database = try await seededDatabase()
        try await database.writer.write { try $0.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('v99')") }

        #expect(try AppDatabase.readSnapshot(in: directory, today: today) == .empty)
    }

    @Test func aNewDatabaseWithNoNightsMeansNoData() throws {
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        _ = try AppDatabase.open(in: directory)

        #expect(try AppDatabase.readSnapshot(in: directory, today: today).content == .noData)
    }

    @Test func learningCountsEarlierNights() {
        var snapshot = WidgetSnapshot(night: today, stressDays: 0, earlierNights: 3)
        #expect(snapshot.content == .learning(nights: 3))
        snapshot.earlierNights = PersonalRange.minimumNights
        #expect(snapshot.content == .ready)
    }

    @Test func staleIsMoreThanTwelveHoursSinceTheLastSyncByTheEntryDate() {
        let synced = at("2026-10-09T06:00:00Z")
        let snapshot = WidgetSnapshot(night: today, stressDays: 0, earlierNights: 9, syncedAt: synced)
        #expect(!snapshot.isStale(at: synced.addingTimeInterval(12 * 3600)))
        #expect(snapshot.isStale(at: synced.addingTimeInterval(12 * 3600 + 1)))
        #expect(!WidgetSnapshot.empty.isStale(at: synced))
    }
}
