import Foundation
import Testing
import VeselCore
import VeselStorage
import VeselWearable
import VeselWearableTesting

struct BandSyncStreamTests {
    let clock = TestClock("2026-10-26T07:00:00Z")
    let database: AppDatabase
    let band: FakeWearableSource
    let sync: BandSync

    init() async throws {
        database = try AppDatabase.inMemory()
        try await database.save(BandInfo(deviceId: "FAKE0001", name: "Polar Loop", pairedAt: at("2026-09-26T08:00:00Z")))
        band = try FakeWearableSource(scenario: .normal, liveInterval: .milliseconds(20))
        sync = BandSync(band: band, database: database, clock: clock)
    }

    /// Starts a sync that holds at the band's `call` until the band answers.
    func syncHeldAt(_ call: String, _ trigger: SyncTrigger) async -> Task<SyncOutcome, Never> {
        await band.hangNext(call)
        let running = Task { await sync.sync(trigger) }
        await waitUntil { await band.hangsOpen == 1 }
        return running
    }

    @Test func liveValuesReachTheApp() async throws {
        await sync.startLiveHeartRate()
        var values = sync.liveHeartRate.makeAsyncIterator()
        let first = try #require(await values.next())
        #expect((60...70).contains(first.bpm))
        #expect(await band.isStreaming)
    }

    @Test func aSyncStopsTheStreamFirstAndRestartsItAfter() async throws {
        await sync.startLiveHeartRate()
        await band.clearCalls()

        #expect(await sync.sync(.bandEvent) == .success)

        let calls = await band.calls
        let stop = try #require(calls.firstIndex(of: "stopLiveHeartRate"))
        let start = try #require(calls.firstIndex(of: "startSync"))
        let end = try #require(calls.lastIndex(of: "stopSync"))
        let restart = try #require(calls.lastIndex(of: "startLiveHeartRate"))
        #expect(stop < start)
        #expect(end < restart)
        #expect(calls.filter { $0 == "startLiveHeartRate" }.count == 1)
        #expect(await sync.isStreaming)
    }

    @Test func startingTheStreamDuringASyncWaitsForIt() async throws {
        let running = await syncHeldAt("fetch", .backgroundRefresh)

        let starting = Task { await sync.startLiveHeartRate() }
        await band.answerHangs()
        _ = await running.value
        await starting.value

        let calls = await band.calls
        #expect(calls.filter { $0 == "startLiveHeartRate" }.count == 1)
        #expect(try #require(calls.firstIndex(of: "startLiveHeartRate")) > (try #require(calls.lastIndex(of: "stopSync"))))
    }

    @Test func noRestartWhenTheAppLeftTheScreenDuringTheSync() async throws {
        await sync.startLiveHeartRate()
        let running = await syncHeldAt("fetch", .bandEvent)

        let stopping = Task { await sync.stopLiveHeartRate() }
        await band.answerHangs()
        _ = await running.value
        await stopping.value

        #expect(await band.calls.filter { $0 == "startLiveHeartRate" }.count == 1)
        #expect(await sync.isStreaming == false)
        #expect(await band.isStreaming == false)
    }

    @Test func overlappingTriggersRunOneSync() async throws {
        await band.setFetchDelay(.milliseconds(20))
        async let fromBand = sync.sync(.bandEvent)
        async let fromRefresh = sync.sync(.backgroundRefresh)
        let outcomes = await [fromBand, fromRefresh]

        #expect(outcomes == [.success, .success])
        #expect(await band.calls.filter { $0 == "startSync" }.count == 1)
        #expect(try await database.latestSyncRun()?.id == 1)
    }

    @Test func aStoppedSyncClearsNothing() async throws {
        await sync.sync(.manual)
        clock.set("2026-10-26T09:00:00Z")
        await band.clearCalls()

        let running = await syncHeldAt("fetch", .backgroundRefresh)
        await sync.cancelSync()

        #expect(await running.value == .failed)
        let calls = await band.calls
        #expect(calls.contains { $0.hasPrefix("delete") } == false)
        #expect(calls.last == "stopSync")
        let run = try #require(try await database.latestSyncRun())
        #expect(run.outcome == .failed)
        #expect(run.detail == "Stopped before it finished")
        #expect(try await database.ledger(FetchKind.allCases).allSatisfy { $0.deletedFromBandAt == nil })
    }

    @Test func aStoppedSyncKeepsWhatItReadAndClearsNothing() async throws {
        try await database.save(BandInfo(deviceId: "FAKE0001", name: "Polar Loop", pairedAt: at("2026-09-27T08:00:00Z")))

        let running = await syncHeldAt("fetch skinTemperature", .backgroundRefresh)
        await sync.cancelSync()

        #expect(await running.value == .failed)
        #expect(try await database.lastStoredDay(.sleep) == day("2026-10-25"))
        #expect(try await database.lastStoredDay(.dailySummary) == day("2026-10-25"))
        #expect(try await database.ledger([.heartRate, .ppi]).isEmpty)
        #expect(try await database.ledger(FetchKind.allCases).allSatisfy { $0.sampleCount > 0 })
        #expect(await band.calls.contains { $0.hasPrefix("delete") } == false)
    }

    /// iOS ending the time mid-write must not cut the write off: a half-written setting leaves the Loop "busy" for good.
    @Test func aStartedWristWriteFinishesEvenWhenStopped() async throws {
        await band.hangNext("setWrist")
        let writing = Task { try await sync.setWrist(.right) }
        await waitUntil { await band.hangsOpen == 1 }
        writing.cancel()
        await band.answerHangs()

        try await writing.value
        #expect(await band.wrist == .right)
    }

    @Test func aBusyLoopIsLoggedAsBusyAtTheStepItRefused() async throws {
        await band.setFailure(.busy)
        #expect(await sync.sync(.manual) == .failed)

        let run = try #require(try await database.latestSyncRuns(limit: 1).first)
        #expect(run.isLoopBusy)
        #expect(run.detail == "Loop busy at sleep")
    }
}
