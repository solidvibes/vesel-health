import Foundation
import GRDB
import Testing
@testable import VeselStorage
import VeselCore

struct StoredDayTests {
    @Test func aStoredRowWithABadDayThrowsInsteadOfCrashing() async throws {
        let database = try AppDatabase.inMemory()
        let end = at("2026-10-25T05:30:00Z")
        var record = try SleepNightRecord(
            SleepNight(night: DayKey(year: 2026, month: 10, day: 25), start: end.addingTimeInterval(-8 * 3600), end: end, goalMinutes: 480, phases: []),
            rawJSON: "{}"
        )
        record.night = "2026-10-xx"
        try await database.writer.write { [record] in try record.upsert($0) }
        await #expect(throws: StorageError.badDay) {
            try await database.writer.read { try SleepNightRecord.fetchOne($0)?.model() }
        }
    }
}
