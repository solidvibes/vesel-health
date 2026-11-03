import Foundation
import GRDB
import Testing
@testable import VeselStorage
import VeselCore

struct MigrationTests {
    @Test func migrationsCreateEveryTable() async throws {
        let database = try AppDatabase.inMemory()
        let tables = try await database.writer.read { db in
            try String.fetchAll(
                db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'grdb_migrations' ORDER BY name")
        }
        #expect(
            tables == [
                "activity_day", "alert_event", "band", "band_ledger", "band_link", "computed_metric", "hr_sample", "nightly_recharge", "ppi_sample",
                "ppi_session", "profile", "raw_export", "setting", "skin_temp_sample", "sleep_night", "sync_run", "workout", "workout_choice",
                "workout_file",
            ])
    }

    @Test func everyHealthTableTracksUploadsAndNothingElseDoes() async throws {
        let database = try AppDatabase.inMemory()
        let tracked = try await database.writer.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT m.name FROM sqlite_master m, pragma_table_info(m.name) c
                    WHERE m.type = 'table' AND c.name = 'uploaded_at' ORDER BY m.name
                    """)
        }
        #expect(tracked == AppDatabase.uploadedTables.sorted())
    }

    @Test func migratingTwiceChangesNothing() async throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue)
        try AppDatabase.migrator.migrate(queue)
        let applied = try await queue.read { try AppDatabase.migrator.appliedIdentifiers($0) }
        #expect(applied == ["v1", "v2", "v3", "v4", "v5", "v6", "v7"])
    }

    @Test func v3AddsAlertsAndSettingsAndKeepsEveryExistingRow() async throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v2")
        try await queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO profile (id, birth_year, sex, height_cm, weight_kg, sleep_goal_minutes, uploaded_at) VALUES (1, 1990, 'male', 180, 75, 480, 100);
                    INSERT INTO band_ledger (day, fetch_kind, stored_at, sample_count, earlier_empty_at) VALUES ('2026-10-20', 'sleep', 200, 0, 150);
                    INSERT INTO computed_metric (kind, day, hour, value, unit, method, method_version, inputs_json, computed_at)
                    VALUES ('recovery.status', '2026-10-20', NULL, 0.5, 'fraction', 'recovery.status', 1, '{}', 300);
                    """)
        }
        try AppDatabase.migrator.migrate(queue)
        let kept = try await queue.read { db in
            (
                profile: try Int.fetchOne(db, sql: "SELECT uploaded_at FROM profile"),
                ledger: try Int.fetchOne(db, sql: "SELECT earlier_empty_at FROM band_ledger WHERE day = '2026-10-20'"),
                metric: try Double.fetchOne(db, sql: "SELECT value FROM computed_metric WHERE kind = 'recovery.status'"),
                alerts: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM alert_event"),
                settings: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM setting")
            )
        }
        #expect(kept.profile == 100)
        #expect(kept.ledger == 150)
        #expect(kept.metric == 0.5)
        #expect(kept.alerts == 0)
        #expect(kept.settings == 0)
        let database = try AppDatabase(queue)
        #expect(try await database.alertSettings() == AlertSettings())
    }

    @Test func refusesADatabaseFromANewerApp() throws {
        let queue = try DatabaseQueue()
        var future = AppDatabase.migrator
        future.registerMigration("future") { _ in }
        try future.migrate(queue)
        #expect(throws: StorageError.newerSchema) { try AppDatabase(queue) }
    }

    @Test func v4AddsBlankWaistAndOutsideVO2maxAndKeepsTheProfile() async throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v3")
        try await queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO profile (id, birth_year, sex, height_cm, weight_kg, sleep_goal_minutes, uploaded_at) VALUES (1, 1990, 'female', 165, 60, 450, 100);
                    """)
        }
        try AppDatabase.migrator.migrate(queue)
        let kept = try await queue.read { db in
            (
                uploadedAt: try Int.fetchOne(db, sql: "SELECT uploaded_at FROM profile"),
                blanks: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM profile WHERE waist_cm IS NULL AND measured_vo2max IS NULL")
            )
        }
        #expect(kept.uploadedAt == 100)
        #expect(kept.blanks == 1)
        let database = try AppDatabase(queue)
        #expect(try await database.profile() == Profile(birthYear: 1990, sex: .female, heightCm: 165, weightKg: 60, sleepGoalMinutes: 450))
    }

    @Test func v5AddsTheConnectionLogAndKeepsEveryExistingRow() async throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v4")
        try await queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO sync_run (trigger, started_at, finished_at, outcome) VALUES ('manual', 100, 110, 'success');
                    INSERT INTO setting (key, value) VALUES ('alerts.morningReport', 'off');
                    """)
        }
        try AppDatabase.migrator.migrate(queue, upTo: "v5")
        let (runs, morningReport, links) = try await queue.read { db in
            (
                try Int.fetchOne(db, sql: "SELECT count(*) FROM sync_run WHERE outcome = 'success'"),
                try String.fetchOne(db, sql: "SELECT value FROM setting WHERE key = 'alerts.morningReport'"),
                try Int.fetchOne(db, sql: "SELECT count(*) FROM band_link")
            )
        }
        #expect(runs == 1)
        #expect(morningReport == "off")
        #expect(links == 0)
    }

    @Test func v6TurnsTheMorningReportOnOnceAndLeavesTheOtherSwitches() async throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v5")
        try await queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO sync_run (trigger, started_at, finished_at, outcome) VALUES ('manual', 100, 110, 'success');
                    INSERT INTO setting (key, value) VALUES ('alerts.morningReport', 'off');
                    INSERT INTO setting (key, value) VALUES ('alerts.lowRecovery', 'off');
                    INSERT INTO setting (key, value) VALUES ('alerts.standUp', 'on');
                    """)
        }
        try AppDatabase.migrator.migrate(queue)
        let database = try AppDatabase(queue)
        let settings = try await database.alertSettings()
        #expect(settings.isOn(.morningReport))
        #expect(!settings.isOn(.lowRecovery))
        #expect(settings.isOn(.standUp))
        #expect(try await database.setting("alerts.lowRecovery") == "off")
        #expect(try await database.setting("alerts.standUp") == "on")
        #expect(try await database.latestSyncRun()?.outcome == .success)

        try await database.setAlert(.morningReport, on: false)
        try AppDatabase.migrator.migrate(queue)
        #expect(try await !database.alertSettings().isOn(.morningReport))
    }

    /// Times and words only, kept 14 days.
    @Test func theConnectionLogKeepsFourteenDays() async throws {
        let database = try AppDatabase.inMemory()
        let old = BandLink(at: at("2026-10-16T23:00:00Z"), event: .disconnected, reason: "connectionLost")
        let kept = BandLink(at: at("2026-10-17T09:00:00Z"), event: .bluetoothOff)
        let now = BandLink(at: at("2026-10-31T08:31:00Z"), event: .connected)
        for link in [old, kept, now] { try await database.save(link) }
        #expect(try await database.bandLinks(since: .distantPast) == [kept, now])
        #expect(try await database.bandLinks(since: at("2026-10-30T00:00:00Z")) == [now])
    }

    @Test func waistAndOutsideVO2maxRoundTripAndClear() async throws {
        let database = try AppDatabase.inMemory()
        let now = at("2026-10-27T08:00:00Z")
        var profile = Profile(birthYear: 1990, sex: .male, heightCm: 180, weightKg: 75, sleepGoalMinutes: 480, waistCm: 84, measuredVO2max: 46)
        try await database.save(profile)
        #expect(try await database.profile() == profile)

        let pending = try await database.pendingUploads(.profile, limit: 10, now: now)
        #expect(pending.first?.data["waist_cm"] == .real(84))
        #expect(pending.first?.data["measured_vo2max"] == .real(46))
        try await database.markUploaded(.profile, pending, at: now)

        profile.waistCm = nil
        profile.measuredVO2max = nil
        try await database.save(profile)
        #expect(try await database.profile() == profile)
        let cleared = try await database.pendingUploads(.profile, limit: 10, now: now)
        #expect(cleared.first?.data["waist_cm"] == .null)
        #expect(cleared.first?.data["measured_vo2max"] == .null)
    }
}
