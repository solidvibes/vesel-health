import Foundation
import Testing
import VeselCore
import VeselStorage
import VeselWearable
import VeselWearableTesting

private actor Steps {
    var all: [SyncStep] = []
    func add(_ step: SyncStep) { all.append(step) }
}

struct BandSyncTests {
    let clock = TestClock("2026-10-26T07:00:00Z")
    let database: AppDatabase
    let band: FakeWearableSource
    let sync: BandSync

    init() async throws {
        database = try AppDatabase.inMemory()
        try await database.save(BandInfo(deviceId: "FAKE0001", name: "Polar Loop", pairedAt: at("2026-09-26T08:00:00Z")))
        band = try FakeWearableSource(scenario: .normal)
        sync = BandSync(band: band, database: database, clock: clock)
    }

    func deletions() async -> [String] {
        await band.calls.filter { $0.hasPrefix("delete") }
    }

    func clearedThrough(_ kind: FetchKind) async throws -> DayKey? {
        try await database.ledger([kind]).filter { $0.deletedFromBandAt != nil }.map(\.day).max()
    }

    /// The day before pairing reads empty, so the first sync can't clear through it yet; the second can.
    func syncTwice() async {
        await sync.sync(.manual)
        clock.set("2026-10-26T09:00:00Z")
        await sync.sync(.manual)
    }

    @Test func aDayReadEmptyOnceIsNotClearedYet() async throws {
        #expect(await sync.sync(.manual) == .success)
        #expect(await deletions().isEmpty)
    }

    @Test func storesEverythingThenClearsThroughTheDayBeforeYesterday() async throws {
        #expect(await sync.sync(.manual) == .success)
        clock.set("2026-10-26T09:00:00Z")
        #expect(await sync.sync(.manual) == .success)

        let calls = await band.calls
        #expect(calls.first == "startSync")
        #expect(calls.last == "stopSync")
        let lastFetch = try #require(calls.lastIndex { $0.hasPrefix("fetch") })
        let firstDelete = try #require(calls.firstIndex { $0.hasPrefix("delete") })
        #expect(lastFetch < firstDelete)
        #expect(await deletions() == StoredDataType.allCases.map { "delete \($0.rawValue) until 2026-10-24" })

        for kind in FetchKind.allCases {
            let ledger = try await database.ledger([kind])
            #expect(ledger.first?.day == day("2026-09-25"))
            #expect(ledger.last?.day == day("2026-10-26"))
            #expect(ledger.filter { $0.deletedFromBandAt != nil }.map(\.day).max() == day("2026-10-24"))
        }
        #expect(try await database.sleepNight(day("2026-10-20")) != nil)
        #expect(try await database.lastSuccessfulSync() == clock.now)
        #expect(try await database.band()?.batteryPercent == 76)
    }

    /// Progress only listens: the steps come in fetch order, and the band is cleared exactly as without it.
    @Test func progressReportsEachStepAndLeavesTheClearingAlone() async throws {
        let steps = Steps()
        #expect(await sync.sync(.manual) { await steps.add($0) } == .success)
        clock.set("2026-10-26T09:00:00Z")
        let first = await steps.all
        #expect(await sync.sync(.manual) { await steps.add($0) } == .success)

        let kinds: [FetchKind] = [.sleep, .nightlyRecharge, .dailySummary, .activitySamples, .skinTemperature, .heartRate, .ppi]
        #expect(first == [.loopFound, .kinds(kinds)] + kinds.map { .fetched($0) })
        #expect(await deletions() == StoredDataType.allCases.map { "delete \($0.rawValue) until 2026-10-24" })
        let calls = await band.calls
        #expect(try #require(calls.lastIndex { $0.hasPrefix("fetch") }) < (try #require(calls.firstIndex { $0.hasPrefix("delete") })))
    }

    @Test func progressOnAFailedReadClearsNothing() async throws {
        let steps = Steps()
        await band.failFetching(.ppi)
        #expect(await sync.sync(.manual) { await steps.add($0) } == .failed)

        #expect(
            await steps.all == [
                .loopFound, .kinds([.sleep, .nightlyRecharge, .dailySummary, .activitySamples, .skinTemperature, .heartRate, .ppi]),
                .fetched(.sleep), .fetched(.nightlyRecharge), .fetched(.dailySummary), .fetched(.activitySamples),
                .fetched(.skinTemperature), .fetched(.heartRate),
            ])
        #expect(await deletions().isEmpty)
        #expect(try await database.ledger(FetchKind.allCases).isEmpty)
    }

    // MARK: Store as each kind arrives, clear only after a whole read

    static let perDayKinds: [FetchKind] = [.sleep, .nightlyRecharge, .dailySummary, .activitySamples, .skinTemperature]

    /// Paired the day after the fixtures start, so the first day read has data. Today (the 26th) reads empty.
    func pairedOnADayWithData() async throws {
        try await database.save(BandInfo(deviceId: "FAKE0001", name: "Polar Loop", pairedAt: at("2026-09-27T08:00:00Z")))
    }

    func emptyRows() async throws -> [LedgerEntry] {
        try await database.ledger(FetchKind.allCases).filter { $0.sampleCount == 0 }
    }

    @Test func aFailedReadKeepsReadingsWithDataAndClearsNothing() async throws {
        try await pairedOnADayWithData()
        await band.failFetching(.ppi)

        #expect(await sync.sync(.manual) == .failed)

        for kind in Self.perDayKinds {
            let ledger = try await database.ledger([kind])
            #expect(ledger.first?.day == day("2026-09-26"))
            #expect(ledger.last?.day == day("2026-10-25"))
            #expect(ledger.allSatisfy { $0.sampleCount > 0 && $0.storedAt == clock.now })
        }
        #expect(try await database.heartRates(from: at("2026-10-24T22:00:00Z"), to: at("2026-10-25T23:00:00Z")).isEmpty == false)
        #expect(try await database.ledger([.heartRate, .ppi]).isEmpty)
        #expect(try await emptyRows().isEmpty)
        #expect(await deletions().isEmpty)
        #expect(await band.calls.last == "stopSync")
    }

    /// The read's watchdog never looks, so the read goes on to the end and only the check after it can catch the drop.
    @Test func aDropThatReconnectsStillCountsForNothing() async throws {
        var limits = ReadLimits.standard
        limits.tick = .seconds(3600)
        let sync = BandSync(band: band, database: database, clock: clock, limits: limits)
        try await pairedOnADayWithData()
        await band.dropMidway(.heartRate, reconnects: true)
        #expect(await sync.sync(.manual) == .failed)
        #expect(await band.calls.contains("fetch ppi"))
        #expect(SyncRunWords.outcome(try #require(try await database.latestSyncRun())) == "didn't finish")

        clock.set("2026-10-26T09:00:00Z")
        await band.dropMidway(.heartRate, reconnects: true)
        #expect(await sync.sync(.manual) == .failed)

        #expect(try await database.ledger([.heartRate, .ppi]).isEmpty)
        #expect(try await emptyRows().isEmpty)
        #expect(await deletions().isEmpty)

        clock.set("2026-10-26T10:00:00Z")
        #expect(await sync.sync(.manual) == .success)
        #expect(await deletions() == StoredDataType.allCases.map { "delete \($0.rawValue) until 2026-10-24" })
        #expect(try await database.ledger([.heartRate]).filter { $0.sampleCount > 0 }.map(\.day).max() == day("2026-10-25"))
    }

    @Test func aDropThatStaysLostCountsForNothing() async throws {
        try await pairedOnADayWithData()
        await band.dropMidway(.heartRate, reconnects: false)

        #expect(await sync.sync(.manual) == .failed)

        #expect(try await database.ledger([.heartRate, .ppi]).isEmpty)
        #expect(try await emptyRows().isEmpty)
        #expect(await deletions().isEmpty)
        #expect(await band.calls.last == "stopSync")
    }

    /// A day never read before that came back empty holds back later days of the same kind until a whole read.
    @Test func aNewEmptyDayHoldsBackLaterDaysUntilAWholeRead() async throws {
        try await pairedOnADayWithData()
        await band.notWorn([day("2026-10-10")])
        await band.failFetching(.ppi)
        #expect(await sync.sync(.manual) == .failed)
        for kind in Self.perDayKinds {
            #expect(try await database.lastStoredDay(kind) == day("2026-10-09"))
        }

        await band.failFetching(nil)
        clock.set("2026-10-26T09:00:00Z")
        #expect(await sync.sync(.manual) == .success)
        let wholeRead = clock.now
        let notWorn = try #require(try await database.ledger([.sleep]).first { $0.day == day("2026-10-10") })
        #expect(notWorn.sampleCount == 0)

        await band.failFetching(.ppi)
        clock.set("2026-10-26T11:00:00Z")
        #expect(await sync.sync(.manual) == .failed)
        let sleep = try await database.ledger([.sleep])
        #expect(sleep.first { $0.day == day("2026-10-11") }?.storedAt == clock.now)
        // Empty days are written only by a whole read.
        #expect(sleep.first { $0.day == day("2026-10-10") } == notWorn)
        #expect(sleep.first { $0.day == day("2026-10-26") }?.storedAt == wholeRead)
    }

    @Test func aWholeReadAfterAFailedOneClearsHeartRateAndBeatToBeat() async throws {
        try await pairedOnADayWithData()
        await band.failFetching(.ppi)
        #expect(await sync.sync(.manual) == .failed)

        await band.failFetching(nil)
        clock.set("2026-10-26T09:00:00Z")
        #expect(await sync.sync(.manual) == .success)

        #expect(try await database.ledger([.ppi]).filter { $0.sampleCount > 0 }.map(\.day).max() == day("2026-10-25"))
        #expect(await deletions().contains("delete autoSample until 2026-10-24"))
    }

    /// A day not worn, read every 10 minutes, settles only once two empty reads are an hour apart.
    @Test func aDayNotWornSettlesAtEmptyReadsAnHourApart() async throws {
        try await pairedOnADayWithData()
        await band.notWorn([day("2026-10-10")])
        for time in ["07:00", "07:10", "07:20"] {
            clock.set("2026-10-26T\(time):00Z")
            #expect(await sync.sync(.manual) == .success)
        }
        #expect(try await clearedThrough(.heartRate) == day("2026-10-09"))

        clock.set("2026-10-26T08:20:00Z")
        #expect(await sync.sync(.manual) == .success)
        #expect(try await clearedThrough(.heartRate) == day("2026-10-24"))
    }

    @Test func todayAndYesterdayStayOnTheBand() async throws {
        await sync.sync(.manual)
        let yesterday = try await band.fetch(.heartRate, from: day("2026-10-25"), through: day("2026-10-25"))
        #expect(yesterday.first?.isEmpty == false)
        let ledger = try await database.ledger([.heartRate])
        #expect(ledger.filter { $0.day >= day("2026-10-25") }.allSatisfy { $0.deletedFromBandAt == nil })
    }

    @Test func daysNotWornDoNotBlockClearing() async throws {
        await band.notWorn([day("2026-10-10"), day("2026-10-11")])
        await syncTwice()
        #expect(try await clearedThrough(.heartRate) == day("2026-10-24"))
        #expect(try await database.ledger([.heartRate]).first { $0.day == day("2026-10-10") }?.sampleCount == 0)
    }

    @Test func aKindMissingForADayBlocksItsType() async throws {
        await band.leaveOut(.ppi, days: [day("2026-10-10")])
        await syncTwice()
        #expect(await deletions().contains("delete autoSample until 2026-10-09"))
        #expect(await deletions().contains("delete sleep until 2026-10-24"))
    }

    @Test func interruptedSyncClearsNothing() async throws {
        await band.failFetching(.ppi)
        #expect(await sync.sync(.manual) == .failed)
        #expect(await deletions().isEmpty)
        #expect(await band.calls.last == "stopSync")
        #expect(try await database.ledger(FetchKind.allCases).isEmpty)
        #expect(try await database.latestSyncRun()?.outcome == .failed)
    }

    /// Days left unconfirmed by the usual window (from the day before the last stored day) are read again.
    @Test func anEmptyDayIsReadAgainUntilItIsConfirmed() async throws {
        await sync.sync(.manual)
        clock.set("2026-10-28T07:00:00Z")
        await sync.sync(.manual)
        // The 26th read empty while it was still going on, so it waits for another read.
        #expect(try await clearedThrough(.heartRate) == day("2026-10-25"))
        #expect(try await database.ledger([.heartRate]).first?.earlierEmptyAt == at("2026-10-26T07:00:00Z"))
    }

    @Test func runningAgainAddsNoDuplicates() async throws {
        await sync.sync(.manual)
        let samples = try await database.heartRates(from: at("2026-10-20T00:00:00Z"), to: at("2026-10-27T00:00:00Z"))
        let ledger = try await database.ledger(FetchKind.allCases)
        clock.set("2026-10-26T09:00:00Z")
        await sync.sync(.manual)
        #expect(try await database.heartRates(from: at("2026-10-20T00:00:00Z"), to: at("2026-10-27T00:00:00Z")) == samples)
        #expect(try await database.ledger(FetchKind.allCases).count == ledger.count)
    }

    @Test(arguments: [SleepRecordingStatus.recording, .unknown])
    func sleepIsLeftAloneWhileTheBandMayStillBeRecording(status: SleepRecordingStatus) async throws {
        await band.setSleepStatus(status)
        #expect(await sync.sync(.manual) == .success)
        let calls = await band.calls
        #expect(!calls.contains("fetch sleep"))
        #expect(!calls.contains("fetch nightlyRecharge"))
        #expect(!calls.contains { $0.hasPrefix("delete sleep") || $0.hasPrefix("delete nightlyRecharge") })
        #expect(try await database.ledger([.sleep, .nightlyRecharge]).isEmpty)
        #expect(calls.contains("fetch heartRate"))
    }

    /// A day cleared off the band comes back empty when fetched again; the stored day must stay as it was.
    @Test func refetchingAClearedDayNeverEmptiesIt() async throws {
        clock.set("2026-10-20T23:00:00Z")  // 01:00 on the 21st in Berlin
        await sync.sync(.manual)
        clock.set("2026-10-21T00:30:00Z")
        await sync.sync(.manual)
        await band.setSleepStatus(.unknown)
        clock.set("2026-10-23T07:00:00Z")
        await sync.sync(.manual)
        #expect(try await clearedThrough(.sleep) == day("2026-10-20"))
        let before = try #require(try await database.ledger([.sleep]).first { $0.day == day("2026-10-20") })
        let night = try await database.sleepNight(day("2026-10-20"))

        await band.setSleepStatus(.stopped)
        await band.clearCalls()
        clock.set("2026-10-23T08:00:00Z")
        #expect(await sync.sync(.manual) == .success)
        #expect(await band.calls.contains("fetch sleep"))

        let after = try #require(try await database.ledger([.sleep]).first { $0.day == day("2026-10-20") })
        #expect(after == before)
        #expect(after.sampleCount > 0)
        #expect(try await database.sleepNight(day("2026-10-20")) == night)
    }

    @Test func bandNotNearbyIsRecordedAndNothingIsTouched() async throws {
        await band.setFailure(.unreachable)
        #expect(await sync.sync(.foreground) == .unreachable)
        #expect(await band.calls.isEmpty)
        #expect(try await database.latestSyncRun()?.outcome == .unreachable)
    }

    @Test func aSecondTriggerWaitsForTheRunningSync() async throws {
        async let first = sync.sync(.manual)
        async let second = sync.sync(.foreground)
        let outcomes = await [first, second]
        #expect(outcomes == [.success, .success])
        #expect(await band.calls.filter { $0 == "startSync" }.count == 1)
    }

    @Test func firstTimeUsePausesTheLiveStreamAndResumesItAfter() async throws {
        let profile = Profile(birthYear: 1990, sex: .male, heightCm: 180, weightKg: 78, sleepGoalMinutes: 480)
        await sync.startLiveHeartRate()
        await band.clearCalls()

        try await sync.firstTimeUse(profile)

        #expect(await band.calls == ["stopLiveHeartRate", "firstTimeUse", "startLiveHeartRate"])
        #expect(await band.profile == profile)
        #expect(await sync.isStreaming)
    }

    @Test func aRefusedFirstTimeUseStillResumesTheLiveStream() async throws {
        await sync.startLiveHeartRate()
        await band.setFailure(.setupFailed)
        await band.clearCalls()

        await #expect(throws: PairingError.setupFailed) {
            try await sync.firstTimeUse(Profile(birthYear: 1990, sex: .male, heightCm: 180, weightKg: 78, sleepGoalMinutes: 480))
        }

        #expect(await band.calls == ["stopLiveHeartRate", "firstTimeUse", "startLiveHeartRate"])
        #expect(await band.profile == nil)
        #expect(await sync.isStreaming)
    }
}
