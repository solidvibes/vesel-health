import Foundation
import Testing
import VeselCore
import VeselStorage
@testable import VeselSync

struct UploaderTests {
    let database: AppDatabase
    let clock = FixedClock(now: at("2026-10-26T08:00:00Z"), timeZone: TimeZone(identifier: "Europe/Berlin")!)
    let config = BackupConfig(host: "mini.local", port: 8443, pin: "pin")
    let token = "t0ken-t0ken-t0ken-t0ken-t0ken-t0ken-t0ken"

    init() throws {
        database = try AppDatabase.inMemory()
    }

    func uploader(_ macMini: FakeMacMini) -> Uploader {
        Uploader(config: config, token: token, database: database, transport: macMini, clock: clock)
    }

    func heartRates(_ count: Int, bpm: Int = 50) -> [HeartRateSample] {
        (0..<count).map { HeartRateSample(time: at("2026-10-26T00:00:00Z").addingTimeInterval(Double($0) * 60), bpm: bpm, trigger: .timed) }
    }

    func storeABandSync() async throws {
        let start = at("2026-10-26T06:00:00Z")
        try await database.save(Profile(birthYear: 1990, sex: .male, heightCm: 180, weightKg: 75, sleepGoalMinutes: 480))
        try await database.save(heartRates: heartRates(3))
        try await database.save(
            PPISession(
                start: start, trigger: .automatic, utcOffsetSeconds: 3600,
                samples: [
                    PPISample(time: start, intervalMs: 900, errorMs: 10, blocker: false, skinContact: true),
                    PPISample(time: start.addingTimeInterval(0.9), intervalMs: 910, errorMs: 10, blocker: false, skinContact: true),
                ]))
        try await database.save(skinTemperatures: [SkinTemperatureSample(time: start, celsius: 33.4)])
    }

    @Test func everythingWaitingIsSentOnceWithTheToken() async throws {
        try await storeABandSync()
        let macMini = FakeMacMini()

        #expect(await uploader(macMini).run() == .backedUp)

        #expect(macMini.sent.first?.path == "/v1/status")
        #expect(macMini.sent.allSatisfy { $0.authorization == "Bearer \(token)" })
        #expect(macMini.batches.map(\.table) == ["profile", "hr_sample", "ppi_session", "ppi_sample", "skin_temp_sample"])
        #expect(macMini.batches.first { $0.table == "ppi_sample" }?.rows.first?["session_start_ts"] as? Int == 1_792_994_400)
        #expect(try await database.pendingUploadCount(now: clock.now) == 0)
        let record = try await BackupRecord.load(from: database)
        #expect(record.lastOutcome == .backedUp)
        #expect(record.lastBackup == clock.now)

        let again = FakeMacMini()
        #expect(await uploader(again).run() == .backedUp)
        #expect(again.batches.isEmpty)
    }

    @Test func theProfileTravelsWithItsWaistAndOutsideVO2max() async throws {
        try await database.save(Profile(birthYear: 1990, sex: .male, heightCm: 180, weightKg: 75, sleepGoalMinutes: 480, waistCm: 84))
        let macMini = FakeMacMini()
        await uploader(macMini).run()

        let row = try #require(macMini.batches.first { $0.table == "profile" }?.rows.first)
        #expect(row["waist_cm"] as? Double == 84)
        #expect(row.keys.contains("measured_vo2max"))
        #expect(row["measured_vo2max"] is NSNull)
    }

    @Test func aBandSyncRightAfterAnUploadQueuesOnlyWhatChanged() async throws {
        try await storeABandSync()
        await uploader(FakeMacMini()).run()

        var samples = heartRates(3)
        samples[2].bpm = 70
        try await database.save(heartRates: samples)
        let macMini = FakeMacMini()
        await uploader(macMini).run()

        #expect(macMini.batches.map(\.table) == ["hr_sample"])
        #expect(macMini.batches.first?.keys == ["1792972920"])
        #expect(macMini.batches.first?.rows.first?["bpm"] as? Int == 70)
    }

    @Test func aRowChangedWhileItsBatchIsOnTheWayStaysQueued() async throws {
        try await database.save(heartRates: heartRates(3))
        let database = database
        let changed = HeartRateSample(time: at("2026-10-26T00:01:00Z"), bpm: 99, trigger: .timed)
        let macMini = FakeMacMini { sent in
            if sent.table == "hr_sample" { try await database.save(heartRates: [changed]) }
            return 200
        }

        await uploader(macMini).run()

        let waiting = try await database.pendingUploads(.hrSample, limit: 10, now: clock.now)
        #expect(waiting.map(\.key) == ["1792972860"])
        #expect(waiting.first?.data["bpm"] == .integer(99))
    }

    @Test func awayFromHomeNothingIsSentOrMarked() async throws {
        try await storeABandSync()
        let before = try await database.pendingUploadCount(now: clock.now)
        let macMini = FakeMacMini { _ in throw URLError(.timedOut) }

        #expect(await uploader(macMini).run() == .away)

        #expect(macMini.sent.count == 1)
        #expect(try await database.pendingUploadCount(now: clock.now) == before)
        #expect(try await BackupRecord.load(from: database) == BackupRecord(lastBackup: nil, lastOutcome: .away))
    }

    @Test func aRefusedTokenAsksForANewQR() async throws {
        try await storeABandSync()
        let macMini = FakeMacMini { _ in 401 }

        let outcome = await uploader(macMini).run()

        #expect(outcome == .unauthorized)
        #expect(outcome.needsNewQR)
        #expect(try await database.pendingUploadCount(now: clock.now) > 0)
    }

    @Test func aFailedBatchKeepsItsRowsAndTheEarlierTablesStayMarked() async throws {
        try await storeABandSync()
        let macMini = FakeMacMini { $0.table == "ppi_session" ? 500 : 200 }

        #expect(await uploader(macMini).run() == .failed)

        #expect(try await database.pendingUploads(.hrSample, limit: 10, now: clock.now).isEmpty)
        #expect(try await database.pendingUploads(.ppiSession, limit: 10, now: clock.now).count == 1)
        #expect(try await database.pendingUploads(.ppiSample, limit: 10, now: clock.now).count == 2)
        #expect(try await BackupRecord.load(from: database).lastBackup == nil)
    }

    @Test func manyRowsGoInBatchesOf500() async throws {
        try await database.save(heartRates: heartRates(1_200))
        let macMini = FakeMacMini()

        await uploader(macMini).run()

        #expect(macMini.batches.map(\.keys.count) == [500, 500, 200])
        #expect(Set(macMini.batches.flatMap(\.keys)).count == 1_200)
    }

    @Test func aBatchStaysUnderTheSizeLimit() async throws {
        let big = String(repeating: "x", count: 1_500_000)
        for day in 20...25 {
            try await database.save(
                SleepNight(
                    night: DayKey(year: 2026, month: 10, day: day), start: at("2026-10-\(day)T22:00:00Z"), end: at("2026-10-\(day)T23:00:00Z"),
                    goalMinutes: nil, phases: []), rawJSON: big)
        }
        let macMini = FakeMacMini()

        await uploader(macMini).run()

        #expect(macMini.batches.map(\.keys.count) == [2, 2, 2])
    }

    @Test func aMacMiniOnAnotherFormatIsLeftAlone() async throws {
        try await storeABandSync()
        let macMini = FakeMacMini { $0.path == "/v1/status" ? 409 : 200 }

        #expect(await uploader(macMini).run() == .otherFormat)
        #expect(macMini.batches.isEmpty)
    }
}
