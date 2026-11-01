import Foundation
import GRDB
import Testing
import VeselCore
@testable import VeselStorage

struct DayLinesTests {
    let clock = FixedClock(now: at("2026-10-09T06:00:00Z"), timeZone: TimeZone(identifier: "Europe/Berlin")!)
    let database: AppDatabase

    func day(_ string: String) -> DayKey { DayKey(string)! }

    init() async throws {
        database = try AppDatabase.inMemory()
    }

    /// Eight nights, 2026-10-01 to 2026-10-08, each 8 h asleep with Polar's 4 of 6, worked out.
    func storeNights() async throws {
        for index in 1...8 {
            try await database.store(night: DayKey(year: 2026, month: 10, day: index), withRecharge: false)
            try await database.save(
                NightlyRecharge(
                    night: DayKey(year: 2026, month: 10, day: index), recoveryIndicator: 4, recoveryIndicatorSubLevel: 50, meanNightlyRecoveryRMSSD: 40),
                rawJSON: "{}"
            )
        }
        try await MetricsUpdater(database: database, clock: clock).updateAfterSync()
    }

    func storeStress(_ day: DayKey, minutes: Double, readings: Double) async throws {
        for (kind, value) in [(MetricKind.stressHighMinutes, minutes), (MetricKind.stressReadings, readings)] {
            try await database.save(
                ComputedMetric(
                    kind: kind, day: day, hour: nil, value: value, unit: "",
                    explanation: Explanation(method: Stress.method, version: Stress.version, inputs: [], text: ""), computedAt: clock.now
                ))
        }
    }

    func lines(from first: String, through last: String) async throws -> [DayKey: DayLines] {
        try await database.writer.read { try AppDatabase.dayLines($0, from: self.day(first), through: self.day(last)) }
    }

    @Test func aRangeOfDaysIsReadInOneCall() async throws {
        try await storeNights()
        let byDay = try await lines(from: "2026-10-07", through: "2026-10-09")

        #expect(byDay.keys.sorted() == [day("2026-10-07"), day("2026-10-08"), day("2026-10-09")])
        #expect(byDay[day("2026-10-07")]?.recovery.state == .learning(soFar: 6, of: 7))
        let eighth = try #require(byDay[day("2026-10-08")])
        #expect(eighth.recovery.state == .inside)
        #expect(eighth.recovery.normal == LineNormal(low: 4))
        #expect(eighth.indicator == 4)
        #expect(eighth.sleep.state == .inside)
        #expect(eighth.sleep.normal == LineNormal(low: 480, high: 480))
        #expect(eighth.asleepMinutes == 480)
        #expect(eighth.calm.state == .none)
        #expect(eighth.highMinutes == nil)
        let ninth = try #require(byDay[day("2026-10-09")])
        #expect(ninth.recovery.state == .none)
        #expect(ninth.sleep.state == .none)
    }

    @Test func aWeekEndingOnAPastDayHoldsWhatTheChartsPlot() async throws {
        try await storeNights()
        try await storeStress(day("2026-10-05"), minutes: 15, readings: 20)
        let week = try await lines(from: "2026-09-29", through: "2026-10-05")

        #expect(week.count == 7)
        #expect(week.keys.max() == day("2026-10-05"))
        #expect(week[day("2026-09-29")]?.indicator == nil)
        #expect(week[day("2026-09-29")]?.recovery.state == LineState.none)
        #expect(week[day("2026-10-05")]?.indicator == 4)
        #expect(week[day("2026-10-05")]?.asleepMinutes == 480)
        #expect(week[day("2026-10-05")]?.highMinutes == 15)
        #expect(week[day("2026-10-01")]?.highMinutes == nil)
    }

    @Test func todaysLinesAreTheNewestNightsAndTodaysCalm() async throws {
        try await storeNights()
        try await storeStress(day("2026-10-09"), minutes: 5, readings: 20)
        let snapshot = try await database.writer.read { try AppDatabase.todaySnapshot($0, day: self.day("2026-10-09"), today: self.day("2026-10-09")) }
        let eighth = try #require(try await lines(from: "2026-10-08", through: "2026-10-08")[day("2026-10-08")])

        #expect(snapshot.earlierNights == 7)
        #expect(eighth.recovery.explanation.inputs.first { $0.name == "nights" }?.value == Double(snapshot.earlierNights))
        #expect(snapshot.lines.recovery == eighth.recovery)
        #expect(snapshot.lines.sleep == eighth.sleep)
        #expect(snapshot.lines.highMinutes == 5)
        #expect(snapshot.lines.calm.state == .learning(soFar: 0, of: 7))
    }

    @Test func calmCountsOnlyWellWornDaysOfTheTwentyEightBefore() async throws {
        let today = day("2026-10-09")
        for offset in 1...7 {
            try await storeStress(today.adding(days: -offset), minutes: 10, readings: 20)
        }
        // Barely worn: neither its own line nor part of the usual.
        try await storeStress(today.adding(days: -8), minutes: 100, readings: 5)
        // Older than 28 days.
        try await storeStress(today.adding(days: -29), minutes: 100, readings: 20)
        try await storeStress(today, minutes: 45, readings: 20)

        let byDay = try await lines(from: "2026-10-01", through: "2026-10-09")

        let calm = try #require(byDay[today]?.calm)
        // Seven days of 10 m: mean 10, SD 0, so the 15-minute floor is the allowance; 45 is above it.
        #expect(calm.normal == LineNormal(high: 15))
        #expect(calm.state == .above)
        #expect(calm.explanation.inputs.first { $0.name == "days" }?.value == 7)
        #expect(byDay[today]?.highMinutes == 45)
        #expect(byDay[today.adding(days: -8)]?.calm.state == InRange.calm(minutes: nil, previous: []).state)
        #expect(byDay[today.adding(days: -8)]?.highMinutes == nil)
    }

    func storeReadings(_ day: DayKey, _ readings: Double) async throws {
        try await database.save(
            ComputedMetric(
                kind: MetricKind.stressReadings, day: day, hour: nil, value: readings, unit: "readings",
                explanation: Explanation(method: Stress.method, version: Stress.version, inputs: [], text: ""), computedAt: clock.now
            ))
    }

    @Test func aWornDayBeforeTheStressBaselineIsLearning() async throws {
        let today = day("2026-10-09")
        for offset in 1...3 {
            try await storeReadings(today.adding(days: -offset), 20)
        }
        try await storeReadings(today.adding(days: -4), 5)
        try await storeReadings(today, 20)

        let byDay = try await lines(from: "2026-10-05", through: "2026-10-09")

        // Three earlier days with at least 10 readings count towards the baseline; the barely-worn one doesn't.
        #expect(byDay[today]?.calm.state == .learning(soFar: 3, of: 7))
        #expect(byDay[today]?.highMinutes == nil)
        #expect(byDay[today.adding(days: -1)]?.calm.state == .learning(soFar: 2, of: 7))
        #expect(byDay[today.adding(days: -4)]?.calm.state == LineState.none)
    }

    @Test func aLongNightIsAboveAndALowRecoveryIsBelow() async throws {
        try await storeNights()
        let ninth = day("2026-10-09")
        let end = ninth.start(in: TimeZone(identifier: "UTC")!).addingTimeInterval(5.5 * 3600)
        try await database.save(
            SleepNight(
                night: ninth, start: end.addingTimeInterval(-10 * 3600), end: end, goalMinutes: 480, phases: [SleepPhase(secondsFromStart: 0, state: .light)]),
            rawJSON: "{}"
        )
        try await database.save(NightlyRecharge(night: ninth, recoveryIndicator: 3, recoveryIndicatorSubLevel: 50, meanNightlyRecoveryRMSSD: 40), rawJSON: "{}")
        try await MetricsUpdater(database: database, clock: clock).updateAfterSync()

        let byDay = try await lines(from: "2026-10-08", through: "2026-10-09")

        // Eight nights of exactly 8 h: the normal is 480 to 480, so 10 h is above it.
        #expect(byDay[day("2026-10-08")]?.sleep.state == .inside)
        #expect(byDay[ninth]?.sleep.state == .above)
        #expect(byDay[ninth]?.sleep.scale?.dot == 1)
        #expect(byDay[ninth]?.recovery.state == .below)
    }

    @Test func noStressNumbersMeansNoCalmLine() async throws {
        let byDay = try await lines(from: "2026-10-09", through: "2026-10-09")
        #expect(byDay[day("2026-10-09")] == .empty)
    }

    func shown(_ dayText: String, today todayText: String = "2026-10-09") async throws -> DayKey? {
        try await database.writer.read { try AppDatabase.shownNight($0, day: self.day(dayText), today: self.day(todayText)) }
    }

    @Test func todaysNightNotInYetIsTheNightBefore() async throws {
        try await storeNights()
        #expect(try await shown("2026-10-09") == day("2026-10-08"))
        let snapshot = try await database.writer.read { try AppDatabase.todaySnapshot($0, day: self.day("2026-10-09"), today: self.day("2026-10-09")) }
        #expect(snapshot.latest?.night == day("2026-10-08"))
        let byDay = try await lines(from: "2026-10-09", through: "2026-10-09")
        #expect(byDay[day("2026-10-09")]?.recovery.state == LineState.none)
        #expect(snapshot.lines.recovery.state == .inside)
    }

    @Test func aPastDayShowsExactlyItsOwnNight() async throws {
        try await storeNights()
        #expect(try await shown("2026-10-05") == day("2026-10-05"))
        #expect(try await shown("2026-09-20") == nil)
        let snapshot = try await database.writer.read { try AppDatabase.todaySnapshot($0, day: self.day("2026-10-05"), today: self.day("2026-10-09")) }
        #expect(snapshot.latest?.night == day("2026-10-05"))
        #expect(snapshot.earlierNights == 4)
        #expect(snapshot.lines.recovery.state == .learning(soFar: 4, of: 7))
    }

    @Test func aPastDayWithoutANightHasNoReportEvenWhenNewerNightsExist() async throws {
        try await storeNights()
        let snapshot = try await database.writer.read { try AppDatabase.todaySnapshot($0, day: self.day("2026-09-20"), today: self.day("2026-10-09")) }
        #expect(snapshot.latest == nil)
        #expect(snapshot.lines.recovery.state == LineState.none)
    }

    @Test func aPastDayHasNoStepsHeartRateOrStressNowFromToday() async throws {
        try await storeNights()
        try await database.save(heartRates: [HeartRateSample(time: at("2026-10-09T05:00:00Z"), bpm: 60, trigger: .timed)])
        let live = try await database.writer.read { try AppDatabase.todaySnapshot($0, day: self.day("2026-10-09"), today: self.day("2026-10-09")) }
        let past = try await database.writer.read { try AppDatabase.todaySnapshot($0, day: self.day("2026-10-05"), today: self.day("2026-10-09")) }
        #expect(live.latestHeartRate?.bpm == 60)
        #expect(past.latestHeartRate == nil)
        #expect(past.steps == nil)
        #expect(past.stressNow == nil)
    }

    @Test func aPastDaysCalmIsThatDaysOwn() async throws {
        try await storeStress(day("2026-10-05"), minutes: 12, readings: 20)
        let past = try await database.writer.read { try AppDatabase.todaySnapshot($0, day: self.day("2026-10-05"), today: self.day("2026-10-09")) }
        #expect(past.lines.highMinutes == 12)
    }

    @Test func theFirstDayIsTheEarliestNightOrHeartRate() async throws {
        let none = try await database.writer.read { try AppDatabase.firstDay($0, zone: self.clock.timeZone) }
        #expect(none == nil)
        try await database.save(heartRates: [HeartRateSample(time: at("2026-10-03T10:00:00Z"), bpm: 60, trigger: .timed)])
        #expect(try await database.writer.read { try AppDatabase.firstDay($0, zone: self.clock.timeZone) } == day("2026-10-03"))
        try await storeNights()
        #expect(try await database.writer.read { try AppDatabase.firstDay($0, zone: self.clock.timeZone) } == day("2026-10-01"))
        try await database.save(heartRates: [HeartRateSample(time: at("2026-09-28T10:00:00Z"), bpm: 60, trigger: .timed)])
        #expect(try await database.writer.read { try AppDatabase.firstDay($0, zone: self.clock.timeZone) } == day("2026-09-28"))
    }
}
