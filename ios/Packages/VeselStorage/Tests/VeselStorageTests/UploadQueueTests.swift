import Foundation
import Testing
import VeselCore
@testable import VeselStorage

struct UploadQueueTests {
    let database: AppDatabase
    let now = at("2026-10-26T08:00:00Z")

    init() throws {
        database = try AppDatabase.inMemory()
    }

    func explanation() -> Explanation {
        Explanation(method: "test", version: 1, inputs: [], text: "Why.")
    }

    @Test func rowsCarryTheirNaturalKeyAndNoLocalIds() async throws {
        let start = at("2026-10-26T06:00:00Z")
        try await database.save(
            PPISession(
                start: start, trigger: .automatic, utcOffsetSeconds: 3600,
                samples: [
                    PPISample(time: start, intervalMs: 900, errorMs: 10, blocker: false, skinContact: true)
                ]))
        try await database.save(
            ComputedMetric(kind: "stress.hourly", day: DayKey("2026-10-26")!, hour: 9, value: 30, unit: "%", explanation: explanation(), computedAt: now))
        try await database.save(
            ComputedMetric(kind: "sleep.asleep", day: DayKey("2026-10-26")!, hour: nil, value: 420, unit: "min", explanation: explanation(), computedAt: now))

        let session = try #require(try await database.pendingUploads(.ppiSession, limit: 10, now: now).first)
        #expect(session.key == "1792994400")
        #expect(session.data["id"] == nil)
        #expect(session.data["uploaded_at"] == nil)
        #expect(session.data["trigger"] == .text("automatic"))

        let sample = try #require(try await database.pendingUploads(.ppiSample, limit: 10, now: now).first)
        #expect(sample.key == "1792994400000")
        #expect(sample.data["session_id"] == nil)
        #expect(sample.data["session_start_ts"] == .integer(1_792_994_400))
        #expect(sample.data["interval_ms"] == .integer(900))

        let keys = try await database.pendingUploads(.computedMetric, limit: 10, now: now).map(\.key).sorted()
        #expect(keys == ["sleep.asleep/2026-10-26", "stress.hourly/2026-10-26/9"])
    }

    @Test func anAlertStillDueWaits() async throws {
        let alert = Alert(kind: .lowRecovery, day: DayKey("2026-10-26")!, title: "T", body: "B", explanation: explanation())
        try await database.save(AlertEvent(alert, firedAt: at("2026-10-26T07:00:00Z")))
        #expect(try await database.pendingUploads(.alertEvent, limit: 10, now: at("2026-10-26T06:00:00Z")).isEmpty)
        #expect(try await database.pendingUploadCount(now: at("2026-10-26T06:00:00Z")) == 0)
        #expect(try await database.pendingUploads(.alertEvent, limit: 10, now: now).map(\.key) == ["lowRecovery/2026-10-26"])
        #expect(try await database.pendingUploadCount(now: now) == 1)
    }

    @Test func onlyRowsUnchangedSinceTheReadAreMarked() async throws {
        let samples = (0..<3).map { HeartRateSample(time: at("2026-10-26T06:00:00Z").addingTimeInterval(Double($0) * 60), bpm: 50, trigger: .timed) }
        try await database.save(heartRates: samples)
        let pending = try await database.pendingUploads(.hrSample, limit: 10, now: now)
        var changed = samples[1]
        changed.bpm = 60
        try await database.save(heartRates: [changed])

        try await database.markUploaded(.hrSample, pending, at: now)

        #expect(try await database.pendingUploads(.hrSample, limit: 10, now: now).map(\.key) == ["1792994460"])
        #expect(try await database.uploadedAt("hr_sample", where: "ts = 1792994400") == now.unixSeconds)
    }

    @Test func pagesFollowOnFromTheLastRow() async throws {
        let samples = (0..<5).map { SkinTemperatureSample(time: at("2026-10-26T06:00:00Z").addingTimeInterval(Double($0) * 60), celsius: 33.5) }
        try await database.save(skinTemperatures: samples)
        let first = try await database.pendingUploads(.skinTempSample, limit: 3, now: now)
        let second = try await database.pendingUploads(.skinTempSample, after: first.last!.rowID, limit: 3, now: now)
        #expect(first.count == 3)
        #expect(second.count == 2)
        #expect(Set(first.map(\.key)).isDisjoint(with: second.map(\.key)))
    }

    @Test func clearingTheMarksQueuesEverythingAgain() async throws {
        try await database.save(heartRates: [HeartRateSample(time: now, bpm: 50, trigger: .timed)])
        try await database.markAllUploaded(at: 1_000)
        #expect(try await database.pendingUploadCount(now: now) == 0)
        try await database.clearUploadMarks()
        #expect(try await database.pendingUploadCount(now: now) == 1)
    }

    @Test func settingsAreSetAndRemovedTogether() async throws {
        try await database.setSettings(["a": "1", "b": "2"])
        try await database.setSettings(["a": nil, "b": "3"])
        #expect(try await database.setting("a") == nil)
        #expect(try await database.setting("b") == "3")
    }
}
