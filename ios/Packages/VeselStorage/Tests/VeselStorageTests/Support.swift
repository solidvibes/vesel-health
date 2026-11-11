import Foundation
import GRDB
@testable import VeselStorage
import VeselCore

extension AppDatabase {
    func uploadedAt(_ table: String, where condition: String) async throws -> Int64? {
        try await writer.read { try Int64.fetchOne($0, sql: "SELECT uploaded_at FROM \(table) WHERE \(condition)") }
    }

    func markAllUploaded(at seconds: Int64) async throws {
        try await writer.write { db in
            for table in AppDatabase.uploadedTables {
                try db.execute(sql: "UPDATE \(table) SET uploaded_at = ?", arguments: [seconds])
            }
        }
    }

    func fetchedAt(day: String) async throws -> Int64? {
        try await writer.read { try Int64.fetchOne($0, sql: "SELECT fetched_at FROM raw_export WHERE day = ?", arguments: [day]) }
    }

    func count(_ table: String) async throws -> Int {
        try await writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM \(table)")! }
    }

    static let uploadedTables = [
        "profile", "sleep_night", "nightly_recharge", "hr_sample", "ppi_session", "ppi_sample",
        "skin_temp_sample", "activity_day", "raw_export", "computed_metric", "alert_event", "workout", "workout_file", "workout_choice",
        "workout_route",
    ]
}

func at(_ iso: String) -> Date {
    try! Date(iso, strategy: .iso8601)
}
