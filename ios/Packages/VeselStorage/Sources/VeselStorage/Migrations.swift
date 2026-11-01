import GRDB

extension AppDatabase {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(
                sql: """
                    CREATE TABLE profile (
                        id INTEGER PRIMARY KEY CHECK (id = 1),
                        birth_year INTEGER NOT NULL,
                        sex TEXT NOT NULL,
                        height_cm REAL NOT NULL,
                        weight_kg REAL NOT NULL,
                        sleep_goal_minutes INTEGER NOT NULL,
                        uploaded_at INTEGER
                    );

                    CREATE TABLE band (
                        id INTEGER PRIMARY KEY CHECK (id = 1),
                        device_id TEXT NOT NULL,
                        name TEXT NOT NULL,
                        paired_at INTEGER NOT NULL,
                        firmware TEXT,
                        battery INTEGER,
                        battery_at INTEGER,
                        disk_free INTEGER,
                        disk_total INTEGER,
                        last_seen_at INTEGER
                    );

                    CREATE TABLE sleep_night (
                        night TEXT PRIMARY KEY,
                        start_at INTEGER NOT NULL,
                        end_at INTEGER NOT NULL,
                        goal_minutes INTEGER,
                        phases_json TEXT NOT NULL,
                        raw_json TEXT NOT NULL,
                        uploaded_at INTEGER
                    );
                    CREATE INDEX sleep_night_start_at ON sleep_night(start_at);

                    CREATE TABLE nightly_recharge (
                        night TEXT PRIMARY KEY,
                        created_at INTEGER,
                        modified_at INTEGER,
                        ans_status REAL,
                        recovery_indicator INTEGER,
                        recovery_indicator_sub_level INTEGER,
                        ans_rate INTEGER,
                        score_rate_obsolete INTEGER,
                        mean_nightly_recovery_rri INTEGER,
                        mean_nightly_recovery_rmssd INTEGER,
                        mean_nightly_recovery_respiration_interval INTEGER,
                        mean_baseline_rri INTEGER,
                        sd_baseline_rri INTEGER,
                        mean_baseline_rmssd INTEGER,
                        sd_baseline_rmssd INTEGER,
                        mean_baseline_respiration_interval INTEGER,
                        sd_baseline_respiration_interval INTEGER,
                        sleep_tip TEXT,
                        vitality_tip TEXT,
                        exercise_tip TEXT,
                        raw_json TEXT NOT NULL,
                        uploaded_at INTEGER
                    );

                    CREATE TABLE hr_sample (
                        ts INTEGER PRIMARY KEY,
                        bpm INTEGER NOT NULL,
                        trigger TEXT NOT NULL,
                        uploaded_at INTEGER
                    );

                    CREATE TABLE ppi_session (
                        id INTEGER PRIMARY KEY,
                        day TEXT NOT NULL,
                        start_ts INTEGER NOT NULL UNIQUE,
                        trigger TEXT NOT NULL,
                        utc_offset_seconds INTEGER NOT NULL,
                        uploaded_at INTEGER
                    );
                    CREATE INDEX ppi_session_day ON ppi_session(day);

                    CREATE TABLE ppi_sample (
                        ts_ms INTEGER PRIMARY KEY,
                        session_id INTEGER NOT NULL REFERENCES ppi_session(id) ON DELETE CASCADE,
                        interval_ms INTEGER NOT NULL,
                        error_ms INTEGER NOT NULL,
                        blocker INTEGER NOT NULL,
                        skin_contact INTEGER NOT NULL,
                        uploaded_at INTEGER
                    );
                    CREATE INDEX ppi_sample_session_id ON ppi_sample(session_id);

                    CREATE TABLE skin_temp_sample (
                        ts INTEGER PRIMARY KEY,
                        celsius REAL NOT NULL,
                        uploaded_at INTEGER
                    );

                    CREATE TABLE activity_day (
                        day TEXT PRIMARY KEY,
                        steps INTEGER NOT NULL,
                        active_seconds INTEGER NOT NULL,
                        calories_json TEXT NOT NULL,
                        uploaded_at INTEGER
                    );

                    CREATE TABLE raw_export (
                        day TEXT NOT NULL,
                        kind TEXT NOT NULL,
                        json TEXT NOT NULL,
                        utc_offset_seconds INTEGER NOT NULL,
                        fetched_at INTEGER NOT NULL,
                        uploaded_at INTEGER,
                        PRIMARY KEY (day, kind)
                    );
                    CREATE INDEX raw_export_fetched_at ON raw_export(fetched_at);

                    CREATE TABLE band_ledger (
                        day TEXT NOT NULL,
                        fetch_kind TEXT NOT NULL,
                        stored_at INTEGER NOT NULL,
                        sample_count INTEGER NOT NULL,
                        deleted_from_band_at INTEGER,
                        PRIMARY KEY (day, fetch_kind)
                    );

                    CREATE TABLE sync_run (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        trigger TEXT NOT NULL,
                        started_at INTEGER NOT NULL,
                        finished_at INTEGER,
                        outcome TEXT,
                        detail TEXT
                    );
                    CREATE INDEX sync_run_started_at ON sync_run(started_at);

                    CREATE TABLE computed_metric (
                        kind TEXT NOT NULL,
                        day TEXT NOT NULL,
                        hour INTEGER,
                        value REAL NOT NULL,
                        unit TEXT NOT NULL,
                        method TEXT NOT NULL,
                        method_version INTEGER NOT NULL,
                        inputs_json TEXT NOT NULL,
                        computed_at INTEGER NOT NULL,
                        uploaded_at INTEGER
                    );
                    CREATE UNIQUE INDEX computed_metric_key ON computed_metric(kind, day, ifnull(hour, -1));
                    """)
        }
        migrator.registerMigration("v2") { db in
            try db.execute(sql: "ALTER TABLE band_ledger ADD COLUMN earlier_empty_at INTEGER")
        }
        migrator.registerMigration("v3") { db in
            try db.execute(
                sql: """
                    CREATE TABLE alert_event (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        kind TEXT NOT NULL,
                        day TEXT NOT NULL,
                        fired_at INTEGER NOT NULL,
                        title TEXT NOT NULL,
                        body TEXT NOT NULL,
                        explanation_json TEXT NOT NULL,
                        uploaded_at INTEGER,
                        UNIQUE (kind, day)
                    );
                    CREATE INDEX alert_event_day ON alert_event(day);

                    CREATE TABLE setting (
                        key TEXT PRIMARY KEY,
                        value TEXT NOT NULL
                    );
                    """)
        }
        migrator.registerMigration("v4") { db in
            try db.execute(
                sql: """
                    ALTER TABLE profile ADD COLUMN waist_cm REAL;
                    ALTER TABLE profile ADD COLUMN measured_vo2max REAL;
                    """)
        }
        migrator.registerMigration("v5") { db in
            try db.execute(
                sql: """
                    CREATE TABLE band_link (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        at INTEGER NOT NULL,
                        event TEXT NOT NULL,
                        reason TEXT
                    );
                    CREATE INDEX band_link_at ON band_link(at);
                    """)
        }
        // The morning report became on by default: a stored choice is dropped once so it follows the new default.
        migrator.registerMigration("v6") { db in
            try db.execute(sql: "DELETE FROM setting WHERE key = 'alerts.morningReport'")
        }
        return migrator
    }
}
