import Foundation
import GRDB
import Testing
import VeselCore
@testable import VeselStorage

/// Each night sleeps 22:00 to 06:00 UTC; its recordings alternate 1000 and 1080 ms over 60 beats, SDNN 40.3376 ms each.
struct SDNNUpdaterTests {
    let database: AppDatabase

    init() async throws {
        database = try AppDatabase.inMemory()
    }

    func night(_ string: String, recordings: Int) async throws {
        let night = DayKey(string)!
        let start = at("\(night.adding(days: -1))T22:00:00Z")
        try await database.save(
            SleepNight(night: night, start: start, end: start.addingTimeInterval(8 * 3600), goalMinutes: nil, phases: []), rawJSON: "{}")
        for index in 0..<recordings {
            try await recording(at: start.addingTimeInterval(Double(index + 1) * 3600))
        }
    }

    func recording(at start: Date) async throws {
        var elapsed = 0
        let samples = (0..<60).map { index -> PPISample in
            let interval = index % 2 == 0 ? 1000 : 1080
            elapsed += interval
            return PPISample(time: start.addingTimeInterval(Double(elapsed) / 1000), intervalMs: interval, errorMs: 5, blocker: false, skinContact: true)
        }
        try await database.save(PPISession(start: start, trigger: .automatic, utcOffsetSeconds: 3600, samples: samples))
    }

    func ledger(_ day: String, _ kind: FetchKind, storedAt iso: String) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO band_ledger (day, fetch_kind, stored_at, sample_count) VALUES (?, ?, ?, 1)
                    ON CONFLICT (day, fetch_kind) DO UPDATE SET stored_at = excluded.stored_at
                    """, arguments: [day, kind.rawValue, at(iso).unixSeconds])
        }
    }

    func pass(_ iso: String) async throws {
        try await database.writer.write { try SDNNUpdater().update($0, now: at(iso)) }
    }

    func sdnn(_ night: String) async throws -> Double? {
        try await database.computedMetric(NightSDNN.kind, day: DayKey(night)!)?.value
    }

    /// Four recordings make no value. A fifth stored without its ledger row isn't seen (the night isn't tried every read);
    /// once a read stores its day after the last pass, the night is worked out again.
    @Test func lateBeatsForAnOldNightCountOnceAReadStoresThem() async throws {
        try await night("2026-10-20", recordings: 4)
        try await pass("2026-10-26T10:00:00Z")
        #expect(try await sdnn("2026-10-20") == nil)

        try await recording(at: at("2026-10-20T03:30:00Z"))
        try await pass("2026-10-26T11:00:00Z")
        #expect(try await sdnn("2026-10-20") == nil)

        try await ledger("2026-10-20", .ppi, storedAt: "2026-10-26T11:30:00Z")
        try await pass("2026-10-26T12:00:00Z")
        let value = try #require(try await sdnn("2026-10-20"))
        #expect(abs(value - 40.33755872716886) < 1e-9)
    }

    @Test func aNightThatNoLongerMakesAValueLosesIt() async throws {
        try await night("2026-10-20", recordings: 5)
        try await pass("2026-10-26T10:00:00Z")
        #expect(try await sdnn("2026-10-20") != nil)

        try await database.writer.write { try $0.execute(sql: "DELETE FROM ppi_session WHERE start_ts = ?", arguments: [at("2026-10-20T03:00:00Z").unixSeconds]) }
        try await ledger("2026-10-21", .sleep, storedAt: "2026-10-26T11:00:00Z")
        try await pass("2026-10-26T12:00:00Z")
        #expect(try await sdnn("2026-10-20") == nil)
    }

    /// 16 nights: the first pass does the newest 14, the next the last 2. A new method version walks history again.
    @Test func historyIsWalkedBackFourteenNightsAPass() async throws {
        for day in 1...16 { try await night(String(format: "2026-10-%02d", day), recordings: 5) }

        try await pass("2026-10-26T10:00:00Z")
        #expect(try await sdnn("2026-10-03") != nil)
        #expect(try await sdnn("2026-10-02") == nil)
        #expect(try await database.setting(SDNNUpdater.fillKey) == "1:2026-10-03")

        try await pass("2026-10-26T11:00:00Z")
        #expect(try await sdnn("2026-10-01") != nil)

        try await database.writer.write { try $0.execute(sql: "DELETE FROM computed_metric") }
        try await database.setSettings([SDNNUpdater.fillKey: "0:2026-10-01"])
        try await pass("2026-10-26T12:00:00Z")
        #expect(try await sdnn("2026-10-16") != nil)
        #expect(try await sdnn("2026-10-02") == nil)
    }
}
