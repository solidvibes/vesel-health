import Foundation
import Testing
import VeselCore
import VeselStorage
import VeselWearable
import VeselWearableTesting
@testable import Vesel

/// About you saved from Loop & settings: the band first, then the phone; nothing stored when the band refuses.
/// A sync that can't reach the band keeps the last real read for Today's "Last read at … ›" link.
@MainActor
struct SyncPipelineTests {
    let profile = Profile(birthYear: 1990, sex: .male, heightCm: 180, weightKg: 78, sleepGoalMinutes: 480)

    func pipeline(failure: FakeFailure? = nil) throws -> (SyncPipeline, FakeWearableSource, AppDatabase) {
        let database = try AppDatabase.inMemory()
        let band = try FakeWearableSource(scenario: .normal, failure: failure)
        let clock = FixedClock(now: try Date("2026-10-26T09:00:00Z", strategy: .iso8601), timeZone: .gmt)
        let bandSync = BandSync(band: band, database: database, clock: clock)
        return (SyncPipeline(bandSync: bandSync, database: database, clock: clock, status: SyncStatusStore(defaults: .throwaway())), band, database)
    }

    @Test func aSaveWritesTheBandOnceThenStoresTheProfile() async throws {
        let (pipeline, band, database) = try pipeline()

        #expect(await pipeline.writeProfile(profile))

        #expect(await band.calls.filter { $0 == "firstTimeUse" }.count == 1)
        #expect(await band.profile == profile)
        #expect(try await database.profile() == profile)
    }

    @Test func aRefusedSaveStoresNothing() async throws {
        let (pipeline, band, database) = try pipeline(failure: .setupFailed)

        #expect(await pipeline.writeProfile(profile) == false)

        #expect(await band.profile == nil)
        #expect(try await database.profile() == nil)
    }

    /// Progress is awaited inside the sync, so nothing can land after the final status.
    @Test func aFinishedSyncEndsIdle() async throws {
        let database = try AppDatabase.inMemory()
        let clock = FixedClock(now: try Date("2026-10-26T09:00:00Z", strategy: .iso8601), timeZone: .gmt)
        let status = SyncStatusStore(defaults: .throwaway())
        let bandSync = BandSync(band: try FakeWearableSource(scenario: .normal), database: database, clock: clock)
        let pipeline = SyncPipeline(bandSync: bandSync, database: database, clock: clock, status: status)
        try await database.save(BandInfo(deviceId: "FAKE0001", name: "Polar Loop", pairedAt: try Date("2026-09-26T08:00:00Z", strategy: .iso8601)))

        #expect(await pipeline.run(.manual) == .success)

        #expect(status.sync == .idle)
    }

    @Test func aStepAfterTheReadEndsIsIgnored() {
        let status = SyncStatusStore(defaults: .throwaway())
        status.report(.loopFound)
        status.stressWorkedOut()
        #expect(status.sync == .idle)

        status.set(.unreachable(lastRead: nil))
        status.report(.fetched(.heartRate))
        #expect(status.sync == .unreachable(lastRead: nil))
    }

    @Test func anUnreachableSyncAfterARealReadKeepsTheLastReadForTodaysLink() async throws {
        let database = try AppDatabase.inMemory()
        let clock = FixedClock(now: try Date("2026-10-26T09:00:00Z", strategy: .iso8601), timeZone: .gmt)
        let status = SyncStatusStore(defaults: .throwaway())
        let bandSync = BandSync(band: try FakeWearableSource(scenario: .normal, failure: .unreachable), database: database, clock: clock)
        let pipeline = SyncPipeline(bandSync: bandSync, database: database, clock: clock, status: status)
        try await database.save(BandInfo(deviceId: "FAKE0001", name: "Polar Loop", pairedAt: try Date("2026-09-26T08:00:00Z", strategy: .iso8601)))
        let lastRead = try Date("2026-10-26T08:12:00Z", strategy: .iso8601)
        let id = try await database.startSyncRun(.launch, at: lastRead.addingTimeInterval(-60))
        try await database.finishSyncRun(id, outcome: .success, detail: nil, at: lastRead)

        #expect(await pipeline.run(.manual) == .unreachable)

        #expect(status.sync == .unreachable(lastRead: lastRead))
    }

    /// iOS ended the app after a read: opening it again within 5 minutes reads nothing, because the stored sleep status says the night is done.
    @Test func openingAgainWithinFiveMinutesAfterAFreshLaunchReadsNothing() async throws {
        let database = try AppDatabase.inMemory()
        let clock = FixedClock(now: try Date("2026-10-26T09:00:00Z", strategy: .iso8601), timeZone: .gmt)
        try await database.save(BandInfo(deviceId: "FAKE0001", name: "Polar Loop", pairedAt: try Date("2026-09-26T08:00:00Z", strategy: .iso8601)))
        let first = SyncPipeline(
            bandSync: BandSync(band: try FakeWearableSource(scenario: .normal), database: database, clock: clock), database: database, clock: clock,
            status: SyncStatusStore(defaults: .throwaway()))
        #expect(await first.run(.manual) == .success)

        let relaunched = SyncPipeline(
            bandSync: BandSync(band: try FakeWearableSource(scenario: .normal), database: database, clock: clock), database: database, clock: clock,
            status: SyncStatusStore(defaults: .throwaway()))

        #expect(await relaunched.run(.foreground, onlyIfDue: true) == nil)
    }

    /// The band was last known to still record the night: opening the app reads, even within 5 minutes.
    @Test func openingWhileTheBandWasStillRecordingTheNightReads() async throws {
        let database = try AppDatabase.inMemory()
        let clock = FixedClock(now: try Date("2026-10-26T09:00:00Z", strategy: .iso8601), timeZone: .gmt)
        try await database.save(BandInfo(deviceId: "FAKE0001", name: "Polar Loop", pairedAt: try Date("2026-09-26T08:00:00Z", strategy: .iso8601)))
        let first = SyncPipeline(
            bandSync: BandSync(band: try FakeWearableSource(scenario: .stillAsleep), database: database, clock: clock), database: database, clock: clock,
            status: SyncStatusStore(defaults: .throwaway()))
        #expect(await first.run(.manual) != nil)

        let relaunched = SyncPipeline(
            bandSync: BandSync(band: try FakeWearableSource(scenario: .stillAsleep), database: database, clock: clock), database: database, clock: clock,
            status: SyncStatusStore(defaults: .throwaway()))

        #expect(await relaunched.run(.foreground, onlyIfDue: true) != nil)
        #expect(await relaunched.run(.bandEvent, onlyIfDue: true) == nil)
    }

    /// Nothing stored about the band's sleep (first launch on this version, a forgotten Loop): opening the app reads, even within 5 minutes.
    @Test func openingWithNoStoredSleepStatusReads() async throws {
        let database = try AppDatabase.inMemory()
        let clock = FixedClock(now: try Date("2026-10-26T09:00:00Z", strategy: .iso8601), timeZone: .gmt)
        try await database.save(BandInfo(deviceId: "FAKE0001", name: "Polar Loop", pairedAt: try Date("2026-09-26T08:00:00Z", strategy: .iso8601)))
        let first = SyncPipeline(
            bandSync: BandSync(band: try FakeWearableSource(scenario: .normal), database: database, clock: clock), database: database, clock: clock,
            status: SyncStatusStore(defaults: .throwaway()))
        #expect(await first.run(.manual) == .success)
        try await database.setSettings([AppDatabase.sleepStatusKey: nil])

        let relaunched = SyncPipeline(
            bandSync: BandSync(band: try FakeWearableSource(scenario: .normal), database: database, clock: clock), database: database, clock: clock,
            status: SyncStatusStore(defaults: .throwaway()))

        #expect(await relaunched.run(.foreground, onlyIfDue: true) != nil)
    }

    /// The clock went back: a last sync that seems to start in the future is not recent, so the next trigger reads.
    @Test func aLastSyncInTheFutureIsNotRecent() async throws {
        let database = try AppDatabase.inMemory()
        let later = FixedClock(now: try Date("2026-10-26T09:00:00Z", strategy: .iso8601), timeZone: .gmt)
        let earlier = FixedClock(now: try Date("2026-10-26T08:00:00Z", strategy: .iso8601), timeZone: .gmt)
        try await database.save(BandInfo(deviceId: "FAKE0001", name: "Polar Loop", pairedAt: try Date("2026-09-26T08:00:00Z", strategy: .iso8601)))
        let first = SyncPipeline(
            bandSync: BandSync(band: try FakeWearableSource(scenario: .normal), database: database, clock: later), database: database, clock: later,
            status: SyncStatusStore(defaults: .throwaway()))
        #expect(await first.run(.manual) == .success)

        let relaunched = SyncPipeline(
            bandSync: BandSync(band: try FakeWearableSource(scenario: .normal), database: database, clock: earlier), database: database, clock: earlier,
            status: SyncStatusStore(defaults: .throwaway()))

        #expect(await relaunched.run(.bandEvent, onlyIfDue: true) != nil)
    }

    // MARK: "I'm up" kept until the Loop is reached (risk: ends sleep on the band)

    /// Last night in the fixtures is 25 October, so "today" is the 25th: once it is read, last night is stored.
    struct Rig {
        let pipeline: SyncPipeline
        let band: FakeWearableSource
        let database: AppDatabase
        let status: SyncStatusStore
        let clock: MovableClock

        var endSleepCalls: Int {
            get async { await band.calls.filter { $0 == "endSleepRecording" }.count }
        }
    }

    static let quick = limits()
    /// A wait for the Loop that never runs out while the test acts.
    static let long = Duration.seconds(600)

    /// The read's limits run on the fake band's uptime, which only its delays and hangs move: a busy run never looks stuck.
    static func limits(wait: Duration = .milliseconds(500), stuck: Duration = .seconds(30)) -> ReadLimits {
        ReadLimits(tapWait: wait, backgroundWait: wait, stuckCall: stuck, backlogCall: stuck, awayGrace: .seconds(2), tick: .milliseconds(10))
    }

    func rig(_ scenario: FakeScenario, failure: FakeFailure? = nil, limits: ReadLimits = quick, awayWait: Duration = .zero) async throws -> Rig {
        let database = try AppDatabase.inMemory()
        try await database.save(BandInfo(deviceId: "FAKE0001", name: "Polar Loop", pairedAt: try Date("2026-09-26T08:00:00Z", strategy: .iso8601)))
        let uptime = ManualUptime()
        let band = try FakeWearableSource(scenario: scenario, failure: failure, awayWait: awayWait, uptime: uptime)
        let clock = MovableClock(now: try Date("2026-10-25T07:30:00Z", strategy: .iso8601), timeZone: .gmt)
        let status = SyncStatusStore(defaults: .throwaway())
        let bandSync = BandSync(band: band, database: database, clock: clock, limits: limits, uptime: { uptime.now })
        return Rig(
            pipeline: SyncPipeline(bandSync: bandSync, database: database, clock: clock, status: status), band: band, database: database, status: status,
            clock: clock)
    }

    @Test func aWaitingTapEndsTheNightOnceThenTheReadFetchesIt() async throws {
        let rig = try await rig(.stillAsleep)
        rig.status.tapImUp(at: rig.clock.now.addingTimeInterval(-60))

        #expect(await rig.pipeline.run(.imUp) == .success)

        #expect(await rig.endSleepCalls == 1)
        #expect(rig.status.imUp == nil)
        #expect(rig.status.sleepEndedAt == rig.clock.now)
        #expect(!rig.status.bandStillRecordingSleep)
        #expect(try await rig.database.hasNight(rig.clock.today))
    }

    @Test func noTapNeverEndsTheNight() async throws {
        let rig = try await rig(.stillAsleep)

        #expect(await rig.pipeline.run(.foreground) == .success)
        #expect(await rig.pipeline.run(.bandEvent) == .success)

        #expect(await rig.endSleepCalls == 0)
        #expect(rig.status.bandStillRecordingSleep)
    }

    /// The band says it records (or can't say) after last night is stored: the morning is over, nothing is ended.
    @Test func aTapAfterLastNightIsStoredEndsNothing() async throws {
        let rig = try await rig(.normal)
        #expect(await rig.pipeline.run(.manual) == .success)
        await rig.band.setSleepStatus(.recording)
        rig.status.tapImUp(at: rig.clock.now)

        #expect(await rig.pipeline.run(.imUp) == .success)

        #expect(await rig.endSleepCalls == 0)
        #expect(rig.status.imUp == nil)
    }

    @Test func aTapWhenTheLoopAlreadyStoppedJustReads() async throws {
        let rig = try await rig(.normal)
        rig.status.tapImUp(at: rig.clock.now)

        #expect(await rig.pipeline.run(.imUp) == .success)

        #expect(await rig.endSleepCalls == 0)
        #expect(rig.status.imUp == nil)
        #expect(try await rig.database.hasNight(rig.clock.today))
    }

    /// Loop not nearby: the tap stays for the next read, what the band last said stays, and no error card.
    @Test func aTapTheLoopNeverGotIsKept() async throws {
        let rig = try await rig(.stillAsleep, failure: .unreachable)
        rig.status.set(sleep: .recording, at: rig.clock.now)
        rig.status.tapImUp(at: rig.clock.now)

        #expect(await rig.pipeline.run(.imUp) == .unreachable)

        #expect(await rig.endSleepCalls == 0)
        #expect(rig.status.imUp == ImUpRequest(tappedAt: rig.clock.now, missedLoop: true))
        #expect(rig.status.bandStillRecordingSleep)
        #expect(rig.status.sync == .idle)
    }

    @Test func aTapSixHoursOldIsDropped() async throws {
        let rig = try await rig(.stillAsleep)
        rig.status.tapImUp(at: rig.clock.now.addingTimeInterval(-ImUpRequest.keptFor))

        #expect(await rig.pipeline.run(.bandEvent) == .success)

        #expect(await rig.endSleepCalls == 0)
        #expect(rig.status.imUp == nil)
    }

    /// Within 5 minutes of a read a check-in reads only to deliver a waiting tap.
    @Test func aWaitingTapSkipsTheFiveMinuteGap() async throws {
        let rig = try await rig(.stillAsleep)
        #expect(await rig.pipeline.run(.manual) == .success)

        #expect(await rig.pipeline.run(.bandCheckIn, onlyIfDue: true) == nil)

        rig.status.tapImUp(at: rig.clock.now)
        #expect(await rig.pipeline.run(.bandCheckIn, onlyIfDue: true) == .success)
        #expect(await rig.endSleepCalls == 1)
    }

    @Test func theShortcutEndsNothingWhenTheLoopCantSayAndLastNightIsStored() async throws {
        let rig = try await rig(.normal)
        #expect(await rig.pipeline.run(.manual) == .success)
        await rig.band.setSleepStatus(.unknown)

        #expect(await rig.pipeline.shortcut() == .success)

        #expect(await rig.endSleepCalls == 0)
    }

    // MARK: Reads wait for the Loop and never hang (31 October)

    /// Out of reach when the read starts, near within the wait: it reads. The try that didn't find it held nothing back.
    @Test func aReadWaitsForTheLoopToComeNear() async throws {
        let rig = try await rig(.normal, failure: .unreachable)
        #expect(await rig.pipeline.run(.bandCheckIn) == .unreachable)
        await rig.band.comesNear(after: .milliseconds(100))

        #expect(await rig.pipeline.run(.bandEvent, onlyIfDue: true) == .success)
    }

    @Test func aBandCallSlowerThanTheLimitStopsTheReadAndClearsNothing() async throws {
        let rig = try await rig(.normal, limits: Self.limits(wait: .zero, stuck: .milliseconds(50)))
        await rig.band.setFetchDelay(.seconds(5))

        #expect(await rig.pipeline.run(.manual) == .failed)

        #expect(SyncRunWords.outcome(try #require(try await rig.database.latestSyncRun())) == "didn't finish")
        #expect(await !rig.band.calls.contains { $0.hasPrefix("delete") })
    }

    @Test func aDropMidReadStopsTheRead() async throws {
        let rig = try await rig(.normal)
        await rig.band.setFetchDelay(.milliseconds(100))
        await rig.band.dropMidway(.sleep, reconnects: true)

        #expect(await rig.pipeline.run(.manual) == .failed)

        let calls = await rig.band.calls
        #expect(!calls.contains("fetch ppi"))
        #expect(!calls.contains { $0.hasPrefix("delete") })
    }

    // MARK: Review findings

    /// A sleep-status or end-sleep call the band never answers stops like any stuck call: the read goes on, nothing hangs.
    @Test func unansweredSleepCallsDontHoldTheRead() async throws {
        let rig = try await rig(.stillAsleep, limits: Self.limits(stuck: .milliseconds(100)))
        rig.status.tapImUp(at: rig.clock.now)
        await rig.band.hangNext("sleepRecordingStatus", for: .seconds(60))

        _ = await rig.pipeline.run(.imUp)

        // Done while the call still hangs.
        #expect(await rig.band.hangsOpen == 1)
        #expect(await rig.endSleepCalls == 0)
        #expect(rig.status.imUp?.missedLoop == true)

        await rig.band.hangNext("endSleepRecording", for: .seconds(60))
        _ = await rig.pipeline.run(.imUp)
        #expect(await rig.band.hangsOpen == 2)
    }

    /// The Loop came near only after the tap had expired: nothing is ended on a stale tap.
    @Test func aTapThatExpiredDuringTheWaitEndsNothing() async throws {
        let rig = try await rig(.stillAsleep, failure: .unreachable, limits: Self.limits(wait: Self.long), awayWait: Self.long)
        rig.status.tapImUp(at: rig.clock.now)

        let read = Task { await rig.pipeline.run(.imUp) }
        await waitUntil { await rig.band.searches == 1 }
        rig.clock.advance(by: ImUpRequest.keptFor + 60)
        await rig.band.comeNear()
        _ = await read.value

        #expect(await rig.endSleepCalls == 0)
        #expect(rig.status.imUp == nil)
    }

    /// iOS ends the time while "I'm up" waits for the Loop: the wait stops now and the tap stays for the next read. A wait
    /// that ran out instead would mark the tap as having missed the Loop.
    @Test func cancellingDuringTheWaitStopsItAndKeepsTheTap() async throws {
        let rig = try await rig(.stillAsleep, failure: .unreachable, limits: Self.limits(wait: Self.long), awayWait: Self.long)
        rig.status.tapImUp(at: rig.clock.now)

        let read = Task { await rig.pipeline.runHeld(.imUp) }
        await waitUntil { await rig.band.searches == 1 }
        read.cancel()
        _ = await read.value

        #expect(await rig.endSleepCalls == 0)
        #expect(rig.status.imUp == ImUpRequest(tappedAt: rig.clock.now))
    }

    /// A long fetch that keeps answering, day by day, is not taken for stuck: each kind takes over a second here, each
    /// day answers within 150 ms.
    @Test func aLongFetchThatKeepsAnsweringIsNotStopped() async throws {
        let rig = try await rig(.normal, limits: Self.limits(stuck: .milliseconds(600)))
        try await rig.database.save(BandInfo(deviceId: "FAKE0001", name: "Polar Loop", pairedAt: try Date("2026-10-20T08:00:00Z", strategy: .iso8601)))
        await rig.band.setDayDelay(.milliseconds(150))

        #expect(await rig.pipeline.run(.manual) == .success)
    }

    /// A stuck call that answers after its read was stopped makes no more band calls, and doesn't touch the next read.
    @Test func aStuckCallThatAnswersLateDoesNothingMore() async throws {
        let rig = try await rig(.normal, limits: Self.limits(stuck: .milliseconds(50)))
        await rig.band.hangNext("fetch", for: .milliseconds(500))
        #expect(await rig.pipeline.run(.manual) == .failed)

        #expect(await rig.pipeline.run(.manual) == .success)
        let afterSecond = await rig.band.calls.count
        await rig.band.answerHangs()
        await waitUntil { await rig.band.hangsOpen == 0 }
        // Room for the late answer to make a call, if it ever would.
        try await Task.sleep(for: .milliseconds(100))

        #expect(await rig.band.calls.count == afterSecond)
        #expect(rig.status.sync == .idle)
    }

    /// The Loop connects while a read that gave up on it is still finishing: the connect reads afresh.
    @Test func aTriggerJoiningAReadThatMissedTheLoopReadsAfresh() async throws {
        let rig = try await rig(.normal, failure: .unreachable, limits: Self.limits(wait: .seconds(2)), awayWait: .seconds(1))
        let first = Task { await rig.pipeline.run(.foreground) }
        await waitUntil { await rig.band.searches == 1 }
        await rig.band.setFailure(nil)

        #expect(await rig.pipeline.run(.bandEvent, onlyIfDue: true) == .success)
        #expect(await first.value == .unreachable)
    }
}
