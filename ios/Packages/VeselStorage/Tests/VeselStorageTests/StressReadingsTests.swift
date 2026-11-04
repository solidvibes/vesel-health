import Foundation
import Synchronization
import Testing
import VeselCore
@testable import VeselStorage

/// A clock the test moves on.
final class MovingClock: VeselClock {
    private let moment: Mutex<Date>
    let timeZone: TimeZone

    init(now: Date, timeZone: TimeZone) {
        moment = Mutex(now)
        self.timeZone = timeZone
    }

    var now: Date {
        get { moment.withLock { $0 } }
        set { moment.withLock { $0 = newValue } }
    }
}

/// Stress readings worked out on read for Trends, on the same days as `StressUpdaterTests`: ten calm-to-stressed readings
/// a day on 1–7 October, and three on the 8th (levels 67.0 at 10:00, 14.8 at 11:00, 40.4 at 12:00).
struct StressReadingsTests {
    let berlin = TimeZone(identifier: "Europe/Berlin")!
    let stored: StressUpdaterTests
    let database: AppDatabase

    init() async throws {
        stored = try await StressUpdaterTests()
        database = stored.database
        try await stored.storeEarlierDays(1...7)
        try await stored.storeToday()
    }

    func day(_ string: String) -> DayKey { DayKey(string)! }

    func readings(_ string: String, now iso: String = "2026-10-08T12:00:00Z") async throws -> [StressReading] {
        try await database.writer.read { try AppDatabase.stressReadings($0, from: day(string), through: day(string), now: at(iso), zone: berlin) }
    }

    @Test func theMiddleReadingInEachHourIsTheStoredHourlyLevel() async throws {
        // A second reading at 10:30 (calmer than 10:00) and at 11:30 (more stressed than 11:00).
        try await database.save(stored.session(day("2026-10-08"), hour: 10, minute: 30, spread: 50))
        try await database.save(stored.session(day("2026-10-08"), hour: 11, minute: 30, spread: 15))
        try await stored.updater.updateAfterSync()
        let found = try await readings("2026-10-08")
        #expect(found.count == 5)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        let byHour = Dictionary(grouping: found) { calendar.component(.hour, from: $0.start) }
        #expect(byHour.mapValues(\.count) == [10: 2, 11: 2, 12: 1])
        for (hour, inHour) in byHour {
            let hourly = try #require(try await database.computedMetric(MetricKind.stressHourly, day: day("2026-10-08"), hour: hour))
            // Two readings: the middle is their mean; one: itself.
            let levels = inHour.map(\.level)
            #expect(abs(levels.reduce(0, +) / Double(levels.count) - hourly.value) < 1e-9)
        }
        #expect(abs(found[0].level - 67.04) < 0.01)
        #expect(abs(found[0].baseline.baseline - StressUpdaterTests.baseline) < 1e-9)
    }

    @Test func aDayStillLearningGivesNoLevels() async throws {
        try await stored.updater.updateAfterSync()
        // 7 October has only six earlier days.
        #expect(try await database.computedMetric(MetricKind.stressReadings, day: day("2026-10-07"))?.value == 10)
        #expect(try await readings("2026-10-07").isEmpty)
        #expect(try await readings("2026-09-30").isEmpty)
    }

    @Test func exerciseAndFlaggedBeatsLeaveNoReading() async throws {
        // The band marked a high-activity heart rate at 11:01 (09:01Z); the 13:00 session has 11 of 40 beats without skin contact.
        try await database.save(heartRates: [HeartRateSample(time: at("2026-10-08T09:01:00Z"), bpm: 150, trigger: .highActivity)])
        try await stored.updater.updateAfterSync()
        #expect(try await readings("2026-10-08").count == 2)
        var flagged = stored.session(day("2026-10-08"), hour: 13, spread: 20, beats: 40)
        flagged.samples = flagged.samples.enumerated().map { index, sample in
            var sample = sample
            sample.skinContact = index >= 11
            return sample
        }
        try await database.save(flagged)
        #expect(try await readings("2026-10-08").count == 2)
    }

    @Test func readingsAfterTheClockAreLeftOutUntilItPassesThem() async throws {
        let clock = MovingClock(now: at("2026-10-08T08:30:00Z"), timeZone: berlin)
        try await MetricsUpdater(database: database, clock: clock).updateAfterSync()
        var values = database.observeStressReadings(from: day("2026-10-08"), through: day("2026-10-08"), clock: clock).makeAsyncIterator()
        #expect(try await values.next()?.map(\.start) == [at("2026-10-08T08:00:00Z")])
        clock.now = at("2026-10-08T12:00:00Z")
        try await MetricsUpdater(database: database, clock: clock).updateAfterSync()
        #expect(try await values.next()?.count == 3)
    }

    @Test func onlyARewriteOfTheDaysNumbersRunsItAgain() async throws {
        let clock = MovingClock(now: at("2026-10-08T12:00:00Z"), timeZone: berlin)
        try await MetricsUpdater(database: database, clock: clock).updateAfterSync()
        var values = database.observeStressReadings(from: day("2026-10-08"), through: day("2026-10-08"), clock: clock).makeAsyncIterator()
        #expect(try await values.next()?.count == 3)
        try await database.markAllUploaded(at: at("2026-10-08T12:30:00Z").unixSeconds)
        // New beats alone don't run it; the stress pass that follows does.
        clock.now = at("2026-10-08T14:00:00Z")
        try await database.save(stored.session(day("2026-10-08"), hour: 13, spread: 50))
        try await MetricsUpdater(database: database, clock: clock).updateAfterSync()
        #expect(try await values.next()?.count == 4)
    }
}
