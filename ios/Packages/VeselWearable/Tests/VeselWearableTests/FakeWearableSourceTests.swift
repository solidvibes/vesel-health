import Foundation
import Testing
import VeselCore
import VeselStorage
import VeselWearable
import VeselWearableTesting

struct FakeWearableSourceTests {
    let first = DayKey(year: 2026, month: 9, day: 26)
    let last = DayKey(year: 2026, month: 10, day: 25)

    @Test(arguments: FetchKind.allCases)
    func normalScenarioHasThirtyReadableDaysOfEveryKind(kind: FetchKind) async throws {
        let band = try FakeWearableSource(scenario: .normal)
        let days = try await band.fetch(kind, from: first, through: last)
        #expect(days.count == 30)
        #expect(days.first?.day == first)
        #expect(days.last?.day == last)
        #expect(days.allSatisfy { $0.kind == kind && !$0.json.isEmpty })
        for payload in days {
            let content = try payload.content()
            #expect((content == .none) == (kind == .activitySamples))
        }
    }

    @Test func normalScenarioHasHourlyStepsForTheStepsBars() async throws {
        let database = try AppDatabase.inMemory()
        try await database.save(
            try await FakeWearableSource(scenario: .normal).fetch(.activitySamples, from: last, through: last), fetchedAt: at("2026-10-26T07:00:00Z"))
        for try await hourly in database.observeHourlySteps(day: last) {
            #expect(hourly.hours.map(\.hour) == Array(7...22))
            return
        }
    }

    @Test func offDayHasTwoPoorNightsAtTheEndAndNothingElseChanged() async throws {
        let normal = try await FakeWearableSource(scenario: .normal).fetch(.nightlyRecharge, from: first, through: last)
        let offDay = try await FakeWearableSource(scenario: .offDay).fetch(.nightlyRecharge, from: first, through: last)
        let recharges = try offDay.map { payload -> NightlyRecharge? in
            if case .nightlyRecharge(let recharge) = try payload.content() { return recharge }
            return nil
        }
        #expect(recharges.suffix(2).map { $0?.recoveryIndicator } == [2, 1])
        #expect(recharges.suffix(2).map { $0?.meanNightlyRecoveryRMSSD } == [29, 27])
        #expect(Array(offDay.dropLast(2)) == Array(normal.dropLast(2)))
    }

    @Test func longNightStoresThatNightsSleep150MinutesHigherAndAboveYourNormal() async throws {
        func lastNight(_ scenario: FakeScenario) async throws -> DayLines {
            let database = try AppDatabase.inMemory()
            let clock = TestClock("2026-10-26T07:00:00Z")
            try await database.save(BandInfo(deviceId: "FAKE0001", name: "Polar Loop", pairedAt: at("2026-09-26T08:00:00Z")))
            #expect(await BandSync(band: try FakeWearableSource(scenario: scenario), database: database, clock: clock).sync(.manual) == .success)
            try await MetricsUpdater(database: database, clock: clock).updateAfterSync()
            for try await lines in database.observeDayLines(from: last, through: last) {
                return try #require(lines[last])
            }
            throw CancellationError()
        }
        let normal = try await lastNight(.normal)
        let long = try await lastNight(.longNight)
        #expect(try #require(long.asleepMinutes) == (try #require(normal.asleepMinutes)) + 150)
        #expect(long.sleep.state == .above)
        #expect(long.recovery.state == .inside)
    }

    @Test func fetchesOnlyTheAskedDays() async throws {
        let band = try FakeWearableSource(scenario: .normal)
        let days = try await band.fetch(.sleep, from: DayKey(year: 2026, month: 10, day: 1), through: DayKey(year: 2026, month: 10, day: 3))
        #expect(days.map(\.day.description) == ["2026-10-01", "2026-10-02", "2026-10-03"])
    }

    @Test func clearedDaysComeBackEmpty() async throws {
        let band = try FakeWearableSource(scenario: .normal)
        let cutoff = DayKey(year: 2026, month: 10, day: 20)
        await band.deleteStored(.autoSample, until: cutoff)
        let heartRates = try await band.fetch(.heartRate, from: first, through: last)
        #expect(heartRates.count == 30)
        #expect(heartRates.filter { !$0.isEmpty }.count == 5)
        #expect(heartRates.filter(\.isEmpty).map(\.day).max() == cutoff)
        #expect(try await band.fetch(.ppi, from: first, through: last).filter { !$0.isEmpty }.count == 5)
        #expect(try await band.fetch(.sleep, from: first, through: last).filter { !$0.isEmpty }.count == 30)
    }

    @Test func carriesTheUtcOffsetAcrossTheClockChange() async throws {
        let band = try FakeWearableSource(scenario: .normal)
        let days = try await band.fetch(.dailySummary, from: DayKey(year: 2026, month: 10, day: 24), through: last)
        #expect(days.map(\.utcOffsetSeconds) == [7200, 3600])
    }

    @Test func factoryResetWipesTheBand() async throws {
        let band = try FakeWearableSource(scenario: .normal)
        try await band.firstTimeUse(Profile(birthYear: 1990, sex: .male, heightCm: 180, weightKg: 75, sleepGoalMinutes: 480), now: at("2026-10-26T07:00:00Z"))
        #expect(await band.profile != nil)
        await band.factoryReset()
        #expect(await band.profile == nil)
        #expect(try await band.fetch(.sleep, from: first, through: last).allSatisfy(\.isEmpty))
    }

    @Test func pairingProblemsAreActedOut() async throws {
        #expect(try await FakeWearableSource(scenario: .pairing).pair() == PairedBand(deviceId: "FAKE0001", name: "Polar Loop"))
        await #expect(throws: PairingError.notFound) { try await FakeWearableSource(scenario: .pairing, failure: .notFound).pair() }
        await #expect(throws: PairingError.refused) { try await FakeWearableSource(scenario: .pairing, failure: .refused).pair() }
        let profile = Profile(birthYear: 1990, sex: .female, heightCm: 168, weightKg: 60, sleepGoalMinutes: 480)
        await #expect(throws: PairingError.setupFailed) {
            try await FakeWearableSource(scenario: .pairing, failure: .setupFailed).firstTimeUse(profile, now: at("2026-10-26T07:00:00Z"))
        }
        #expect(try await FakeWearableSource(scenario: .normal, failure: .unreachable).reachable(within: .zero) == false)
    }
}
