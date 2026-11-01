import Foundation
import Testing
@testable import VeselStorage
import VeselCore

struct UpsertTests {
    let night = DayKey(year: 2026, month: 10, day: 26)

    func sleep(goal: Int = 480) -> SleepNight {
        SleepNight(
            night: night,
            start: at("2026-10-25T22:30:00Z"),
            end: at("2026-10-26T06:10:00Z"),
            goalMinutes: goal,
            phases: [.init(secondsFromStart: 0, state: .light), .init(secondsFromStart: 1800, state: .deep)]
        )
    }

    @Test func aRowIsStoredOnceKeepsItsUploadMarkUntilItChanges() async throws {
        let database = try AppDatabase.inMemory()
        try await database.save(sleep(), rawJSON: "{}")
        try await database.markAllUploaded(at: 1_000)
        try await database.save(sleep(), rawJSON: "{}")
        #expect(try await database.count("sleep_night") == 1)
        #expect(try await database.sleepNight(night) == sleep())
        #expect(try await database.uploadedAt("sleep_night", where: "night = '2026-10-26'") == 1_000)

        try await database.save(sleep(goal: 450), rawJSON: "{}")
        #expect(try await database.uploadedAt("sleep_night", where: "night = '2026-10-26'") == nil)
        #expect(try await database.sleepNight(night)?.goalMinutes == 450)
    }

    @Test func profileAndBandKeepOneRow() async throws {
        let database = try AppDatabase.inMemory()
        try await database.save(.init(birthYear: 1990, sex: .male, heightCm: 180, weightKg: 75, sleepGoalMinutes: 480))
        try await database.save(.init(birthYear: 1990, sex: .male, heightCm: 180, weightKg: 74, sleepGoalMinutes: 480))
        #expect(try await database.count("profile") == 1)
        #expect(try await database.profile()?.weightKg == 74)

        try await database.save(.init(deviceId: "A1", name: "Polar Loop A1", pairedAt: at("2026-10-26T08:00:00Z")))
        try await database.save(.init(deviceId: "A1", name: "Polar Loop A1", pairedAt: at("2026-10-26T08:00:00Z"), batteryPercent: 80))
        #expect(try await database.count("band") == 1)
        #expect(try await database.band()?.batteryPercent == 80)
    }

    @Test func nullToValueCountsAsAChange() async throws {
        let database = try AppDatabase.inMemory()
        try await database.save(NightlyRecharge(night: night), rawJSON: "{}")
        try await database.markAllUploaded(at: 1_000)
        try await database.save(NightlyRecharge(night: night, ansStatus: 4.2, recoveryIndicator: 4), rawJSON: "{}")
        #expect(try await database.uploadedAt("nightly_recharge", where: "night = '2026-10-26'") == nil)
        #expect(try await database.nightlyRecharge(night)?.ansStatus == 4.2)
    }

    @Test func samplesAreStoredOncePerTimestamp() async throws {
        let database = try AppDatabase.inMemory()
        let samples = [
            HeartRateSample(time: at("2026-10-26T06:00:00Z"), bpm: 52, trigger: .timed),
            HeartRateSample(time: at("2026-10-26T06:05:00Z"), bpm: 55, trigger: .timed),
        ]
        try await database.save(heartRates: samples)
        try await database.markAllUploaded(at: 1_000)
        try await database.save(heartRates: samples)
        #expect(try await database.count("hr_sample") == 2)
        #expect(try await database.uploadedAt("hr_sample", where: "bpm = 52") == 1_000)
        #expect(try await database.heartRates(from: at("2026-10-26T06:00:00Z"), to: at("2026-10-26T06:05:00Z")) == [samples[0]])
    }

    @Test func ppiSessionIsStoredOnceWithItsSamples() async throws {
        let database = try AppDatabase.inMemory()
        let session = PPISession(
            start: at("2026-10-26T03:00:00Z"),
            trigger: .automatic,
            utcOffsetSeconds: 3600,
            samples: [
                PPISample(time: at("2026-10-26T03:00:01Z"), intervalMs: 1010, errorMs: 6, blocker: false, skinContact: true),
                PPISample(time: at("2026-10-26T03:00:02Z"), intervalMs: 990, errorMs: 5, blocker: false, skinContact: true),
            ]
        )
        try await database.save(session)
        try await database.save(session)
        #expect(try await database.count("ppi_session") == 1)
        #expect(try await database.count("ppi_sample") == 2)
    }

    @Test func refetchKeepsTheUploadMarkUntilThePayloadChanges() async throws {
        let database = try AppDatabase.inMemory()
        let payload = BandPayload(day: night, kind: .heartRate, json: "{\"samples\":[]}", utcOffsetSeconds: 3600, sampleCount: 0)
        try await database.save([payload], fetchedAt: at("2026-10-26T07:00:00Z"))
        try await database.markAllUploaded(at: 1_000)
        try await database.save([payload], fetchedAt: at("2026-10-26T08:00:00Z"))
        #expect(try await database.uploadedAt("raw_export", where: "day = '2026-10-26'") == 1_000)
        #expect(try await database.fetchedAt(day: "2026-10-26") == at("2026-10-26T07:00:00Z").unixSeconds)
        #expect(try await database.count("band_ledger") == 1)

        var changed = payload
        changed.json = #"{"samples":[{"hr":52,"time":"06:00:00","triggerType":"TIMED"}]}"#
        changed.sampleCount = 1
        try await database.save([changed], fetchedAt: at("2026-10-26T08:00:00Z"))
        #expect(try await database.uploadedAt("raw_export", where: "day = '2026-10-26'") == nil)
        #expect(try await database.fetchedAt(day: "2026-10-26") == at("2026-10-26T08:00:00Z").unixSeconds)
        let ledger = try await database.writer.read { try BandLedgerRecord.fetchAll($0) }
        #expect(ledger.map(\.sampleCount) == [1])
    }

    @Test func dayAndHourlyMetricsAreSeparateRowsAndOnlyAChangedValueIsSentAgain() async throws {
        let database = try AppDatabase.inMemory()
        let explanation = Explanation(method: "test", version: 1, inputs: [.init(name: "rmssd", value: 42, unit: "ms")], text: "From last night's HRV.")
        let daily = ComputedMetric(
            kind: "recovery", day: night, hour: nil, value: 70, unit: "%", explanation: explanation, computedAt: at("2026-10-26T07:00:00Z"))
        var hourly = daily
        hourly.hour = 9

        try await database.save(daily)
        try await database.save(hourly)
        try await database.markAllUploaded(at: 1_000)
        var recomputed = daily
        recomputed.computedAt = at("2026-10-26T08:00:00Z")
        try await database.save(recomputed)

        #expect(try await database.count("computed_metric") == 2)
        #expect(try await database.uploadedAt("computed_metric", where: "hour IS NULL") == 1_000)
        #expect(try await database.computedMetric("recovery", day: night) == daily)
        #expect(try await database.computedMetric("recovery", day: night, hour: 9)?.hour == 9)

        recomputed.value = 64
        try await database.save(recomputed)
        #expect(try await database.count("computed_metric") == 2)
        #expect(try await database.uploadedAt("computed_metric", where: "hour IS NULL") == nil)
        #expect(try await database.computedMetric("recovery", day: night) == recomputed)
    }
}
