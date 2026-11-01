import Foundation
import GRDB
import Testing
import VeselCore
@testable import VeselStorage

struct StressUpdaterTests {
    let berlin = TimeZone(identifier: "Europe/Berlin")!
    let utc = TimeZone(identifier: "UTC")!
    let database: AppDatabase
    let updater: MetricsUpdater

    /// Ten readings a day, each 30 beats alternating 1000 ms and 1000 + d ms: every difference is d, so RMSSD = d.
    static let spreads = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
    /// 70 values (each of the ten seven times). Sorted index 55 is 80 and 56 is 90, so the 80th percentile is
    /// ln 80 + 0.2 × (ln 90 − ln 80) = 4.4056; the 5th percentile is ln 10 = 2.3026.
    static let baseline = log(80.0) + 0.2 * (log(90.0) - log(80.0))
    static let floor = log(10.0)

    init() async throws {
        database = try AppDatabase.inMemory()
        updater = MetricsUpdater(database: database, clock: FixedClock(now: at("2026-10-08T12:00:00Z"), timeZone: berlin))
        try await database.save(Profile(birthYear: 1990, sex: .male, heightCm: 180, weightKg: 75, sleepGoalMinutes: 480))
    }

    /// Local 2026-10 is UTC+2 until the 25th.
    func session(_ day: DayKey, hour: Int, minute: Int = 0, spread: Int, offset: Int = 7200, beats count: Int = 30) -> PPISession {
        let start = day.start(in: utc).addingTimeInterval(Double(hour * 3600 + minute * 60 - offset))
        var elapsed = 0
        let samples = (0..<count).map { index -> PPISample in
            let interval = index % 2 == 0 ? 1000 : 1000 + spread
            elapsed += interval
            return PPISample(time: start.addingTimeInterval(Double(elapsed) / 1000), intervalMs: interval, errorMs: 5, blocker: false, skinContact: true)
        }
        return PPISession(start: start, trigger: .automatic, utcOffsetSeconds: offset, samples: samples)
    }

    func storeEarlierDays(_ days: ClosedRange<Int>) async throws {
        for number in days {
            for (index, spread) in Self.spreads.enumerated() {
                try await database.save(session(DayKey(year: 2026, month: 10, day: number), hour: 8 + index, spread: spread))
            }
        }
    }

    /// 2026-10-08: level 67.0 (high) at 10:00, 14.8 (calm) at 11:00, 40.4 (moderate) at 12:00.
    func storeToday() async throws {
        let today = day("2026-10-08")
        try await database.save(session(today, hour: 10, spread: 20))
        try await database.save(session(today, hour: 11, spread: 60))
        try await database.save(session(today, hour: 12, spread: 35))
    }

    func day(_ string: String) -> DayKey { DayKey(string)! }

    func input(_ metric: ComputedMetric?, _ name: String) -> Double? {
        metric?.explanation.inputs.first { $0.name == name }?.value
    }

    func hourly(_ string: String, _ hour: Int) async throws -> ComputedMetric? {
        try await database.computedMetric(MetricKind.stressHourly, day: day(string), hour: hour)
    }

    @Test func sevenEarlierDaysMakeTheBaselineAndTheDaysLevels() async throws {
        try await storeEarlierDays(1...7)
        try await storeToday()
        try await updater.updateAfterSync()

        let readings = try #require(try await database.computedMetric(MetricKind.stressReadings, day: day("2026-10-08")))
        #expect(readings.value == 3)
        #expect(input(readings, "baselineDays") == 7)
        #expect(input(readings, "baselineReadings") == 70)
        let baseline = try #require(input(readings, "baseline"))
        let floor = try #require(input(readings, "floor"))
        #expect(abs(baseline - Self.baseline) < 1e-9)
        #expect(abs(floor - Self.floor) < 1e-9)
        #expect(input(readings, "beats") == 90)
        #expect(input(readings, "flagged") == 0)

        // level = (4.4056 − ln d) ÷ (4.4056 − 2.3026) × 100
        let ten = try #require(try await hourly("2026-10-08", 10))
        #expect(abs(ten.value - 67.04) < 0.01)
        #expect(StressLevel(level: ten.value) == .high)
        let eleven = try #require(try await hourly("2026-10-08", 11))
        let twelve = try #require(try await hourly("2026-10-08", 12))
        #expect(abs(eleven.value - 14.80) < 0.01)
        #expect(abs(twelve.value - 40.43) < 0.01)

        // One high reading at 10:00; the next reading is an hour later, so it counts for the 15-minute cap.
        #expect(try await database.computedMetric(MetricKind.stressHighMinutes, day: day("2026-10-08"))?.value == 15)
        let now = try #require(try await database.computedMetric(MetricKind.stressNow, day: day("2026-10-08")))
        #expect(abs(now.value - 40.43) < 0.01)
    }

    @Test func sixEarlierDaysAreStillLearningAndStoreOnlyTheReadings() async throws {
        try await storeEarlierDays(2...7)
        try await storeToday()
        try await updater.updateAfterSync()
        let readings = try #require(try await database.computedMetric(MetricKind.stressReadings, day: day("2026-10-08")))
        #expect(readings.value == 3)
        #expect(input(readings, "baselineDays") == 6)
        #expect(input(readings, "baseline") == nil)
        #expect(try await hourly("2026-10-08", 10) == nil)
        #expect(try await database.computedMetric(MetricKind.stressHighMinutes, day: day("2026-10-08")) == nil)
        #expect(try await database.computedMetric(MetricKind.stressNow, day: day("2026-10-08")) == nil)
        let snapshot = try await database.writer.read { try AppDatabase.todaySnapshot($0, day: day("2026-10-08"), today: day("2026-10-08")) }
        #expect(snapshot.stressDays == 6)
        #expect(snapshot.stressNow == nil)
    }

    @Test func hoursWithoutReadingsStayEmpty() async throws {
        try await storeEarlierDays(1...7)
        try await storeToday()
        try await updater.updateAfterSync()
        #expect(try await hourly("2026-10-08", 9) == nil)
        #expect(try await hourly("2026-10-08", 13) == nil)
        let rows = try await database.writer.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM computed_metric WHERE kind = 'stress.hourly' AND day = '2026-10-08'")!
        }
        #expect(rows == 3)
    }

    @Test func aReadingDuringHighActivityIsLeftOutAndItsHourGoes() async throws {
        try await storeEarlierDays(1...7)
        try await storeToday()
        try await updater.updateAfterSync()
        #expect(try await hourly("2026-10-08", 11) != nil)
        // 11:00 local is 09:00 UTC; the band marked a high-activity heart rate at 11:01.
        try await database.save(heartRates: [HeartRateSample(time: at("2026-10-08T09:01:00Z"), bpm: 150, trigger: .highActivity)])
        try await updater.recomputeStress(days: [day("2026-10-08")])
        #expect(try await hourly("2026-10-08", 11) == nil)
        let readings = try await database.computedMetric(MetricKind.stressReadings, day: day("2026-10-08"))
        #expect(readings?.value == 2)
        #expect(input(readings, "duringExercise") == 1)
    }

    @Test func flaggedBeatsAreCountedAndLeaveNoReading() async throws {
        try await storeEarlierDays(1...7)
        var flagged = session(day("2026-10-08"), hour: 10, spread: 20, beats: 40)
        flagged.samples = flagged.samples.enumerated().map { index, sample in
            var sample = sample
            sample.blocker = index < 11
            return sample
        }
        try await database.save(flagged)
        try await updater.updateAfterSync()
        let readings = try #require(try await database.computedMetric(MetricKind.stressReadings, day: day("2026-10-08")))
        #expect(readings.value == 0)
        #expect(input(readings, "flagged") == 11)
        #expect(input(readings, "tooFewBeats") == 1)
        #expect(try await hourly("2026-10-08", 10) == nil)
    }

    @Test func aReadingAfterTheClockIsNotCounted() async throws {
        try await storeEarlierDays(1...7)
        try await storeToday()
        // 10:30 local is 08:30 UTC: only the 10:00 reading has happened.
        let early = MetricsUpdater(database: database, clock: FixedClock(now: at("2026-10-08T08:30:00Z"), timeZone: berlin))
        try await early.updateAfterSync()
        #expect(try await database.computedMetric(MetricKind.stressReadings, day: day("2026-10-08"))?.value == 1)
        #expect(try await hourly("2026-10-08", 11) == nil)
    }

    @Test func aChangedDayRecomputesTheLaterDaysThatUseIt() async throws {
        try await storeEarlierDays(1...7)
        try await storeToday()
        try await updater.updateAfterSync()
        let before = input(try await database.computedMetric(MetricKind.stressReadings, day: day("2026-10-08")), "baseline")
        // Day 1 gets ten more readings, all of them 100: calmer than the rest.
        for index in 0..<10 {
            try await database.save(session(day("2026-10-01"), hour: 8 + index, minute: 30, spread: 100))
        }
        let done = try await updater.recomputeStress(days: [day("2026-10-01")])
        #expect(done.contains(day("2026-10-08")))
        let after = input(try await database.computedMetric(MetricKind.stressReadings, day: day("2026-10-08")), "baseline")
        let lower = try #require(before)
        let higher = try #require(after)
        #expect(higher > lower)
    }

    @Test func daysAlreadyInPlaceAreLeftAloneAndNewOnesAreWorkedOut() async throws {
        try await storeEarlierDays(1...7)
        try await storeToday()
        try await updater.updateAfterSync()
        let stress = StressUpdater(clock: FixedClock(now: at("2026-10-08T12:00:00Z"), timeZone: berlin))
        let touched = try await database.writer.read { try stress.touchedDays($0, today: day("2026-10-08")) }
        #expect(touched == [day("2026-10-06"), day("2026-10-07"), day("2026-10-08")])
        try await database.save(session(day("2026-09-20"), hour: 10, spread: 50))
        let again = try await database.writer.read { try stress.touchedDays($0, today: day("2026-10-08")) }
        #expect(again.contains(day("2026-09-20")))
    }

    /// What a sync writes for a day it stored: one ledger row per band data type, with the time it was stored.
    func ledger(_ string: String, _ kind: FetchKind, storedAt iso: String) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO band_ledger (day, fetch_kind, stored_at, sample_count) VALUES (?, ?, ?, 1)
                    ON CONFLICT (day, fetch_kind) DO UPDATE SET stored_at = excluded.stored_at
                    """, arguments: [string, kind.rawValue, at(iso).unixSeconds])
        }
    }

    @Test func anOlderDayReStoredWithMoreBeatsIsRecomputedAndOneNotReStoredIsNot() async throws {
        try await storeEarlierDays(1...7)
        try await storeToday()
        for number in 1...8 { try await ledger("2026-10-0\(number)", .ppi, storedAt: "2026-10-08T11:00:00Z") }
        try await updater.updateAfterSync()
        #expect(try await database.computedMetric(MetricKind.stressReadings, day: day("2026-10-02"))?.value == 10)

        // A later sync re-reads 2 October, which now has five more readings; 3 October is not re-read.
        for index in 0..<5 {
            try await database.save(session(day("2026-10-02"), hour: 8 + index, minute: 30, spread: 40))
        }
        try await ledger("2026-10-02", .ppi, storedAt: "2026-10-08T13:00:00Z")
        let later = FixedClock(now: at("2026-10-08T14:00:00Z"), timeZone: berlin)
        let stress = StressUpdater(clock: later)
        let touched = try await database.writer.read { try stress.touchedDays($0, today: day("2026-10-08")) }
        #expect(touched == [day("2026-10-02"), day("2026-10-06"), day("2026-10-07"), day("2026-10-08")])

        try await MetricsUpdater(database: database, clock: later).updateAfterSync()
        #expect(try await database.computedMetric(MetricKind.stressReadings, day: day("2026-10-02"))?.value == 15)
        let again = try await database.writer.read { try stress.touchedDays($0, today: day("2026-10-08")) }
        #expect(!again.contains(day("2026-10-02")))
    }

    @Test func aDayReStoredUnchangedIsRecomputedOnce() async throws {
        try await storeEarlierDays(1...7)
        try await storeToday()
        try await updater.updateAfterSync()
        let uploaded = at("2026-10-08T12:30:00Z")
        try await database.markAllUploaded(at: uploaded.unixSeconds)

        // A heart-rate re-read of 2 October with nothing new in it.
        try await ledger("2026-10-02", .heartRate, storedAt: "2026-10-08T13:00:00Z")
        let later = FixedClock(now: at("2026-10-08T14:00:00Z"), timeZone: berlin)
        let stress = StressUpdater(clock: later)
        #expect(try await database.writer.read { try stress.touchedDays($0, today: day("2026-10-08")) }.contains(day("2026-10-02")))
        try await MetricsUpdater(database: database, clock: later).updateAfterSync()
        #expect(try await !database.writer.read { try stress.touchedDays($0, today: day("2026-10-08")) }.contains(day("2026-10-02")))
        // Nothing changed, so nothing is sent to the Mac again.
        #expect(try await database.uploadedAt("computed_metric", where: "kind = 'stress.readings' AND day = '2026-10-02'") == uploaded.unixSeconds)

        // A later re-read that does bring a new reading changes the numbers, so they go to the Mac again.
        try await database.save(session(day("2026-10-02"), hour: 8, minute: 30, spread: 40))
        try await ledger("2026-10-02", .ppi, storedAt: "2026-10-08T15:00:00Z")
        try await MetricsUpdater(database: database, clock: FixedClock(now: at("2026-10-08T16:00:00Z"), timeZone: berlin)).updateAfterSync()
        #expect(try await database.computedMetric(MetricKind.stressReadings, day: day("2026-10-02"))?.value == 11)
        #expect(try await database.uploadedAt("computed_metric", where: "kind = 'stress.readings' AND day = '2026-10-02'") == nil)
    }

    @Test func theTodayScreenAndTheStressScreenReadTheStoredNumbers() async throws {
        try await storeEarlierDays(1...7)
        try await storeToday()
        try await updater.updateAfterSync()
        let snapshot = try await database.writer.read { try AppDatabase.todaySnapshot($0, day: day("2026-10-08"), today: day("2026-10-08")) }
        #expect(snapshot.stressDays == 7)
        #expect(snapshot.stressNow?.band == .moderate)
        #expect(snapshot.stressNow?.windowStart == at("2026-10-08T10:00:00Z"))

        let report = try await database.writer.read { try AppDatabase.stressReport($0, day: day("2026-10-08")) }
        #expect(report.hourly.map(\.hour) == [10, 11, 12])
        #expect(report.readings?.value == 3)
        #expect(report.isLearning == false)
    }

    @Test func firstDayIsTheDayOfTheEarliestHeartRateInTheClocksZone() async throws {
        let none = try await database.writer.read { try AppDatabase.firstDay($0, zone: berlin) }
        #expect(none == nil)

        try await database.save(heartRates: [HeartRateSample(time: at("2026-10-03T10:00:00Z"), bpm: 60, trigger: .timed)])
        let one = try await database.writer.read { try AppDatabase.firstDay($0, zone: berlin) }
        #expect(one == day("2026-10-03"))

        // 22:30 UTC on the 1st is 00:30 on the 2nd in Berlin (UTC+2).
        try await database.save(heartRates: [
            HeartRateSample(time: at("2026-10-01T22:30:00Z"), bpm: 58, trigger: .timed),
            HeartRateSample(time: at("2026-10-05T10:00:00Z"), bpm: 61, trigger: .timed),
        ])
        let edge = try await database.writer.read { try AppDatabase.firstDay($0, zone: berlin) }
        #expect(edge == day("2026-10-02"))
        let inUTC = try await database.writer.read { try AppDatabase.firstDay($0, zone: utc) }
        #expect(inUTC == day("2026-10-01"))
    }

    @Test func aPastDaysReportHoldsThatDaysNumbers() async throws {
        try await storeEarlierDays(1...7)
        try await storeToday()
        try await updater.updateAfterSync()
        let past = try await database.writer.read { try AppDatabase.stressReport($0, day: day("2026-10-05")) }
        #expect(past.day == day("2026-10-05"))
        #expect(past.readings?.value == 10)
        #expect(past.baselineDays == 4)
        let empty = try await database.writer.read { try AppDatabase.stressReport($0, day: day("2026-09-20")) }
        #expect(empty.readings == nil)
        #expect(empty.hourly.isEmpty)
    }

    @Test func trendsCarryTheSeries() async throws {
        try await storeEarlierDays(1...7)
        try await storeToday()
        for number in 1...7 {
            let night = DayKey(year: 2026, month: 10, day: number)
            try await database.store(night: night)
            let asleep = night.start(in: utc).addingTimeInterval(2 * 3600)
            try await database.save(heartRates: [HeartRateSample(time: asleep, bpm: 50 + number, trigger: .timed)])
        }
        try await updater.updateAfterSync()
        let trends = try await database.writer.read { try AppDatabase.trends($0, today: day("2026-10-08")) }
        #expect(trends.series[Contributor.sleep.kind]?.count == 7)
        #expect(trends.series[MetricKind.recoveryStatus]?.count == 7)
        #expect(trends.series[MetricKind.stressHighMinutes]?.count == 1)
        #expect(trends.series[Contributor.hrv.kind]?.count == 7)
        #expect(trends.series[MetricKind.sleepLowestHeartRate]?.count == 7)
        #expect(trends.series[Contributor.breathing.kind]?.count == 7)
    }

    @Test func exerciseHeartRateIsRestingPlusFortyPercentOfTheReserve() throws {
        // Born 1990, on 2026-10-26: 36 years, maximum 220 − 36 = 184. Resting 55: reserve 129, 55 + 0.4 × 129 = 106.6.
        let resting = [day("2026-10-25"): 55.0, day("2026-10-27"): 99.0]
        let limits = StressInputs.ActivityLimits(birthYear: 1990, resting: resting)
        let found = try #require(limits.heartRate(on: day("2026-10-26")))
        #expect(abs(found - 106.6) < 1e-9)
        #expect(limits.heartRate(on: day("2026-10-24")) == nil)
        #expect(StressInputs.ActivityLimits(birthYear: nil, resting: resting).heartRate(on: day("2026-10-26")) == nil)
    }
}
