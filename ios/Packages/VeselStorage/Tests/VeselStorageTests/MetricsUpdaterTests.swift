import Foundation
import GRDB
import Testing
import VeselCore
@testable import VeselStorage

struct MetricsUpdaterTests {
    let berlin = TimeZone(identifier: "Europe/Berlin")!
    let clock: FixedClock
    let database: AppDatabase
    let updater: MetricsUpdater

    /// Eight nights, 2026-10-01 to 2026-10-08. HRV 30 34 38 42 46 50 54 and then 26.
    /// The first seven give mean 42 and SD 8, so night eight (26) is exactly 2 SDs below.
    static let hrv = [30, 34, 38, 42, 46, 50, 54, 26]

    init() async throws {
        clock = FixedClock(now: at("2026-10-09T06:00:00Z"), timeZone: berlin)
        database = try AppDatabase.inMemory()
        updater = MetricsUpdater(database: database, clock: clock)
        try await database.save(Profile(birthYear: 1990, sex: .male, heightCm: 180, weightKg: 75, sleepGoalMinutes: 480))
        for (index, hrv) in Self.hrv.enumerated() {
            try await store(night: DayKey(year: 2026, month: 10, day: index + 1), hrv: hrv)
        }
    }

    func store(night: DayKey, hrv: Int) async throws {
        let end = night.start(in: TimeZone(identifier: "UTC")!).addingTimeInterval(5.5 * 3600)
        try await database.save(
            SleepNight(
                night: night, start: end.addingTimeInterval(-8 * 3600), end: end, goalMinutes: 480, phases: [SleepPhase(secondsFromStart: 0, state: .light)]),
            rawJSON: "{}"
        )
        try await database.save(
            NightlyRecharge(
                night: night, recoveryIndicator: 4, recoveryIndicatorSubLevel: 50,
                meanNightlyRecoveryRRI: 1000, meanNightlyRecoveryRMSSD: hrv, meanNightlyRecoveryRespirationInterval: 4000
            ),
            rawJSON: "{}"
        )
    }

    func reading(_ night: String, _ contributor: Contributor) async throws -> ContributorReading? {
        try await database.computedMetric(contributor.kind, day: day(night)).flatMap(ContributorReading.init)
    }

    func day(_ string: String) -> DayKey { DayKey(string)! }

    @Test func storesTheSleepNumbersWithTheirExplanations() async throws {
        try await updater.updateAfterSync()
        let asleep = try #require(try await database.computedMetric(MetricKind.sleepAsleep, day: day("2026-10-08")))
        #expect(asleep.value == 480)
        #expect(asleep.explanation.method == "sleep.summary")
        #expect(asleep.explanation.version == 1)
        #expect(!asleep.explanation.text.isEmpty)
        #expect(try await database.computedMetric("ring.sleep", day: day("2026-10-08")) == nil)
        let status = try #require(try await database.computedMetric(MetricKind.recoveryStatus, day: day("2026-10-08")))
        #expect(abs(status.value - 3.5 / 6) < 1e-9)
        #expect(status.explanation.version == 2)
    }

    @Test func sevenEarlierNightsMakeTheRangeAndSixDoNot() async throws {
        try await updater.updateAfterSync()
        let seventh = try #require(try await reading("2026-10-07", .hrv))
        #expect(seventh.nights == 6)
        #expect(seventh.verdict == .learning(nights: 6))
        let eighth = try #require(try await reading("2026-10-08", .hrv))
        #expect(eighth.nights == 7)
        #expect(eighth.range == PersonalRange(mean: 42, sd: 8, nights: 7))
        #expect(eighth.verdict == .lower)
        #expect(eighth.usualText() == "34 ms–50 ms")
    }

    @Test func aChangedNightRecomputesTheLaterNightsThatUseIt() async throws {
        try await updater.updateAfterSync()
        try await store(night: day("2026-10-02"), hrv: 74)
        let done = try await updater.recompute(nights: [day("2026-10-02")])
        #expect(done == Set((2...8).map { DayKey(year: 2026, month: 10, day: $0) }))
        // 30 74 38 42 46 50 54 add up to 334.
        let eighth = try #require(try await reading("2026-10-08", .hrv))
        #expect(abs((eighth.range?.mean ?? 0) - 334.0 / 7) < 1e-9)
    }

    /// Readings stored part way through a read, with no ledger row yet, still reach a recent night, which follows them as more arrive.
    @Test func aRecentNightFollowsReadingsThatArriveLater() async throws {
        func heartRates(_ samples: [(time: String, bpm: Int)]) -> BandPayload {
            let json = samples.map { #"{"hr":\#($0.bpm),"time":"\#($0.time)","triggerType":"TIMED"}"# }.joined(separator: ",")
            return BandPayload(
                day: day("2026-10-08"), kind: .heartRate, json: #"{"date":"2026-10-08","samples":[\#(json)]}"#, utcOffsetSeconds: 7200,
                sampleCount: samples.count)
        }
        try await database.saveReadings([heartRates([("02:00:00", 58)])])
        try await updater.updateAfterSync()
        #expect(try await database.computedMetric(MetricKind.sleepLowestHeartRate, day: day("2026-10-08"))?.value == 58)

        try await database.saveReadings([heartRates([("02:00:00", 58), ("04:00:00", 49)])])
        try await updater.updateAfterSync()
        #expect(try await database.computedMetric(MetricKind.sleepLowestHeartRate, day: day("2026-10-08"))?.value == 49)
    }

    @Test func aNightFarBackIsLeftAloneWhenItsNumbersAreInPlace() async throws {
        try await updater.updateAfterSync()
        let again = try await updater.updateAfterSync()
        #expect(again == [day("2026-10-07"), day("2026-10-08")])
    }

    @Test func aNightWithNoNumbersYetIsWorkedOut() async throws {
        try await updater.updateAfterSync()
        try await database.store(night: day("2026-09-20"))
        let done = try await updater.updateAfterSync()
        #expect(done.contains(day("2026-09-20")))
        #expect(try await database.computedMetric(MetricKind.sleepAsleep, day: day("2026-09-20")) != nil)
    }

    @Test func nightsStoredUnderAnOlderMethodVersionAreRecomputed() async throws {
        try await updater.updateAfterSync()
        let old = ComputedMetric(
            kind: MetricKind.sleepAsleep, day: day("2026-10-01"), hour: nil, value: 1, unit: "min",
            explanation: Explanation(method: SleepSummary.method, version: 0, inputs: [], text: "old"), computedAt: clock.now
        )
        try await database.save(old)
        let done = try await updater.updateAfterSync()
        #expect(done.contains(day("2026-10-01")))
        let fresh = try #require(try await database.computedMetric(MetricKind.sleepAsleep, day: day("2026-10-01")))
        #expect(fresh.explanation.version == SleepSummary.version)
        #expect(fresh.value == 480)
    }

    @Test func contributorsStoredUnderVersionOneAreRecomputed() async throws {
        try await updater.updateAfterSync()
        let old = ComputedMetric(
            kind: Contributor.sleep.kind, day: day("2026-10-01"), hour: nil, value: 1, unit: "min",
            explanation: Explanation(method: RecoveryContributors.method, version: 1, inputs: [], text: "old"), computedAt: clock.now
        )
        try await database.save(old)
        let done = try await updater.updateAfterSync()
        #expect(done.contains(day("2026-10-01")))
        let fresh = try #require(try await database.computedMetric(Contributor.sleep.kind, day: day("2026-10-01")))
        #expect(fresh.explanation.version == 2)
        #expect(fresh.value == 480)
    }

    @Test func aNightWithoutARechargeStillGetsItsSleep() async throws {
        try await database.store(night: day("2026-10-09"), withRecharge: false)
        try await updater.updateAfterSync()
        #expect(try await database.computedMetric(MetricKind.sleepAsleep, day: day("2026-10-09")) != nil)
        #expect(try await database.computedMetric(MetricKind.recoveryStatus, day: day("2026-10-09")) == nil)
        #expect(try await reading("2026-10-09", .hrv) == nil)
    }

    @Test func aNumberWhoseInputWentAwayIsRemoved() async throws {
        try await updater.updateAfterSync()
        try await database.save(NightlyRecharge(night: day("2026-10-08"), meanNightlyRecoveryRRI: 1000), rawJSON: "{}")
        try await updater.recompute(nights: [day("2026-10-08")])
        #expect(try await database.computedMetric(MetricKind.recoveryStatus, day: day("2026-10-08")) == nil)
        #expect(try await reading("2026-10-08", .hrv) == nil)
        #expect(try await reading("2026-10-08", .restingHeartRate) != nil)
        #expect(try await database.computedMetric(MetricKind.sleepAsleep, day: day("2026-10-08"))?.value == 480)
    }

    @Test func todayReadsTheNewestNightAndHowManyCameBefore() async throws {
        try await updater.updateAfterSync()
        try await database.save(ActivityDay(day: day("2026-10-09"), steps: 4321, activeSeconds: 100, calories: .init(bmr: 1, activity: 1, total: 2)))
        let snapshot = try await database.writer.read { try AppDatabase.todaySnapshot($0, day: day("2026-10-09"), today: day("2026-10-09")) }
        #expect(snapshot.latest?.night == day("2026-10-08"))
        #expect(snapshot.earlierNights == 7)
        #expect(snapshot.steps == 4321)
        #expect(snapshot.latest?.contributors.count == 4)
    }

    @Test func aNightReportCarriesWhatTheScreensNeed() async throws {
        try await updater.updateAfterSync()
        let report = try #require(try await database.writer.read { try AppDatabase.nightReport($0, day("2026-10-08")) })
        #expect(report.sleep?.phases.count == 1)
        #expect(report.recharge?.meanNightlyRecoveryRMSSD == 26)
        #expect(report.status?.word == "OK")
        #expect(report.stageMinutes(.light) == 480)
        #expect(report.contributors.map(\.contributor) == [.hrv, .restingHeartRate, .sleep, .breathing])
    }
}

extension AppDatabase {
    func store(night: DayKey, withRecharge: Bool = true) async throws {
        let end = night.start(in: TimeZone(identifier: "UTC")!).addingTimeInterval(5.5 * 3600)
        try await save(
            SleepNight(
                night: night, start: end.addingTimeInterval(-8 * 3600), end: end, goalMinutes: 480, phases: [SleepPhase(secondsFromStart: 0, state: .light)]),
            rawJSON: "{}"
        )
        if withRecharge {
            try await save(
                NightlyRecharge(night: night, recoveryIndicator: 3, meanNightlyRecoveryRMSSD: 40, meanNightlyRecoveryRespirationInterval: 4000), rawJSON: "{}")
        }
    }
}
