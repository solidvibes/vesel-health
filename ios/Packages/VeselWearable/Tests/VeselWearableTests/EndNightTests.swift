import Foundation
import Testing
import VeselCore
import VeselStorage
import VeselWearable
import VeselWearableTesting

struct EndNightTests {
    let clock = TestClock("2026-10-26T07:00:00Z")
    let database: AppDatabase
    let band: FakeWearableSource
    let sync: BandSync

    init() async throws {
        database = try AppDatabase.inMemory()
        try await database.save(BandInfo(deviceId: "FAKE0001", name: "Polar Loop", pairedAt: at("2026-09-26T08:00:00Z")))
        band = try FakeWearableSource(scenario: .stillAsleep)
        sync = BandSync(band: band, database: database, clock: clock)
    }

    @Test func readingTheSleepStatusAsksTheBandAndChangesNothing() async throws {
        #expect(await sync.readSleepStatus(within: .zero) == .recording)
        #expect(await sync.sleepStatus == .recording)
        #expect(await band.sleepStatus == .recording)
        await band.setFailure(.unreachable)
        #expect(await sync.readSleepStatus(within: .zero) == nil)
    }

    @Test func syncingNeverEndsSleep() async throws {
        #expect(await band.sleepStatus == .recording)
        await sync.sync(.foreground)
        await sync.sync(.bandEvent)
        await sync.sync(.backgroundRefresh)
        #expect(await band.sleepStatus == .recording)
        #expect(await !band.calls.contains("endSleepRecording"))
        #expect(await sync.sleepStatus == .recording)
    }

    @Test func whileSleepRecordsNoNightIsFetched() async throws {
        await sync.sync(.foreground)
        let calls = await band.calls
        #expect(!calls.contains("fetch sleep"))
        #expect(!calls.contains("fetch nightlyRecharge"))
        #expect(try await database.sleepNight(day("2026-10-25")) == nil)
    }

    @Test func onlyAnExplicitCallEndsSleepAndTheNextSyncReadsTheNight() async throws {
        await sync.sync(.foreground)
        try await sync.endSleepRecording()
        #expect(await band.sleepStatus == .stopped)
        #expect(await band.calls.filter { $0 == "endSleepRecording" }.count == 1)
        #expect(await sync.sleepStatus == .stopped)

        await sync.sync(.manual)
        #expect(await band.calls.contains("fetch sleep"))
        #expect(try await database.sleepNight(day("2026-10-25")) != nil)
    }

    @Test func endingTheNightWaitsForARunningSync() async throws {
        await band.hangNext("fetch")
        let running = Task { await sync.sync(.foreground) }
        await waitUntil { await band.hangsOpen == 1 }
        let ending = Task { try await sync.endSleepRecording() }
        await band.answerHangs()
        _ = await running.value
        try await ending.value
        let calls = await band.calls
        let end = try #require(calls.firstIndex(of: "endSleepRecording"))
        let stop = try #require(calls.lastIndex(of: "stopSync"))
        #expect(stop < end)
    }

    @Test func scenariosActOutTheirSituation() async throws {
        let first = try FakeWearableSource(scenario: .firstDay)
        #expect(try await first.fetch(.sleep, from: day("2026-09-29"), through: day("2026-09-30")).map(\.isEmpty) == [false, true])
        let none = try FakeWearableSource(scenario: .noSleep)
        #expect(try await none.fetch(.sleep, from: day("2026-10-01"), through: day("2026-10-01")).first?.isEmpty == true)
        #expect(try await none.fetch(.heartRate, from: day("2026-10-01"), through: day("2026-10-01")).first?.isEmpty == false)
        let away = try FakeWearableSource(scenario: .unreachable)
        #expect(await !away.reachable(within: .zero))
    }
}
