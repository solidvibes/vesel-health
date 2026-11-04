import Foundation
import Testing
import VeselCore
import VeselStorage
import VeselWearable
import VeselWearableTesting
@testable import Vesel

/// Body and the pages' W, M and 3M: the fake band's nights, stored and worked out by a real sync, shown inside the window only,
/// in the owner's units.
@MainActor
struct BodyModelTests {
    let end = DayKey(year: 2026, month: 10, day: 25)

    func synced() async throws -> (AppDatabase, FixedClock) {
        let database = try AppDatabase.inMemory()
        let clock = FixedClock(now: try Date("2026-10-26T09:00:00Z", strategy: .iso8601), timeZone: .gmt)
        let bandSync = BandSync(band: try FakeWearableSource(scenario: .normal), database: database, clock: clock)
        let pipeline = SyncPipeline(bandSync: bandSync, database: database, clock: clock, status: SyncStatusStore(defaults: .throwaway()))
        try await database.save(BandInfo(deviceId: "FAKE0001", name: "Polar Loop", pairedAt: try Date("2026-09-26T08:00:00Z", strategy: .iso8601)))
        #expect(await pipeline.run(.manual) == .success)
        return (database, clock)
    }

    @Test func aWeekShowsOnlyItsOwnNights() async throws {
        let (database, clock) = try await synced()
        let week = BodyModel(database: database, clock: clock, units: UnitsStore(), period: .week, endingOn: end)
        await observe(week.observe) { week.isReady }

        #expect(week.firstDay == DayKey(year: 2026, month: 10, day: 19))
        let nights = week.inRange(.hrv).map(\.metric.day)
        #expect(!nights.isEmpty)
        #expect(nights.allSatisfy { $0 >= week.firstDay && $0 <= end })
        #expect(week.domain == week.firstDay.start(in: .gmt)...end.adding(days: 1).start(in: .gmt))
    }

    @Test func skinTemperatureFollowsTheUnitsSetting() async throws {
        let (database, clock) = try await synced()
        let units = UnitsStore()
        let following = Task { await units.observe(database) }
        defer { following.cancel() }
        let model = BodyModel(database: database, clock: clock, units: units, period: .week, endingOn: end)
        await observe(model.observe) { model.isReady }
        let celsius = try #require(model.inRange(.skinTemperature).last?.value)
        #expect(model.points(.skinTemperature).last?.value == celsius)

        try await database.setUnits(.us)
        await waitUntil { model.units == .us }
        #expect(model.points(.skinTemperature).last?.value == celsius * 9 / 5 + 32)
    }

    @Test func aNightHasAMarkExactlyWhenItHasANormal() async throws {
        let (database, clock) = try await synced()
        let model = BodyModel(database: database, clock: clock, units: UnitsStore(), period: .quarter, endingOn: end)
        await observe(model.observe) { model.isReady }

        for kind in [TrendKind.recovery, .hrv, .restingHeartRate, .lowestHeartRate, .breathing, .skinTemperature, .sleep] {
            for night in model.inRange(kind) {
                #expect((night.mark != nil) == (night.normal != nil), "\(kind) \(night.metric.day)")
            }
            #expect(model.points(kind).map(\.mark) == model.inRange(kind).map(\.mark))
        }
    }

    @Test func contributorMarksComeFromTheirReadings() async throws {
        let (database, clock) = try await synced()
        let model = BodyModel(database: database, clock: clock, units: UnitsStore(), period: .quarter, endingOn: end)
        await observe(model.observe) { model.isReady }

        for night in model.inRange(.hrv) {
            #expect(night.mark == ContributorReading(night.metric)?.mark)
        }
        for night in model.inRange(.recovery) {
            #expect(night.mark == RecoveryStatus(night.metric)?.mark)
        }
    }

    @Test func theLowestHeartRateIsBetterLowerAndExplainsItsNormalOnRead() async throws {
        let (database, clock) = try await synced()
        let model = BodyModel(database: database, clock: clock, units: UnitsStore(), period: .quarter, endingOn: end)
        await observe(model.observe) { model.isReady }

        for night in model.inRange(.lowestHeartRate) {
            #expect((night.normalExplanation != nil) == (night.normal != nil))
            guard let normal = night.normal else { continue }
            let range = PersonalRange(mean: (normal.lowerBound + normal.upperBound) / 2, sd: (normal.upperBound - normal.lowerBound) / 2, nights: 0)
            #expect(night.mark == NormalMark(verdict: range.verdict(of: night.value), better: .lower))
            #expect(night.normalExplanation?.method == PersonalRange.method)
        }
    }

    @Test func inBedAndEfficiencyAreReadOnlyWhereAskedAndHaveTheirNormalsOnRead() async throws {
        let (database, clock) = try await synced()
        let model = BodyModel(
            database: database, clock: clock, units: UnitsStore(), period: .quarter, endingOn: end,
            kinds: [MetricKind.sleepInBed, MetricKind.sleepEfficiency]
        )
        await observe(model.observe) { model.isReady }
        #expect(model.inRange(.hrv).isEmpty)

        let inBed = model.inRange(.inBed)
        #expect(!inBed.isEmpty)
        for night in inBed {
            #expect(night.mark == nil)
            #expect((night.normal != nil) == (night.normalExplanation != nil))
        }
        #expect(inBed.contains { $0.normal != nil })
        let withNormal = try #require(inBed.last { $0.normal != nil })
        #expect(withNormal.normalExplanation?.method == PersonalRange.method)
        let picture = try #require(model.picture(.inBed, night: withNormal))
        #expect(picture.mark == nil)

        let efficiency = model.inRange(.efficiency)
        #expect(!efficiency.isEmpty)
        for night in efficiency {
            guard let normal = night.normal else {
                #expect(night.mark == nil)
                continue
            }
            #expect(normal.upperBound <= 100)
            #expect((night.mark == .inside) == normal.contains(night.value))
            #expect((night.mark == .better(.above)) == (night.value > normal.upperBound))
            #expect(night.normalExplanation?.method == "range28Low")
        }
    }

    @Test func inBedAndEfficiencyPeriodsAreAveragesWithoutMarks() async throws {
        let (database, clock) = try await synced()
        let model = BodyModel(
            database: database, clock: clock, units: UnitsStore(), period: .month, endingOn: end,
            kinds: [MetricKind.sleepInBed, MetricKind.sleepEfficiency]
        )
        await observe(model.observe) { model.isReady }

        let inBedAverage = try #require(PeriodWindow.average(model.inRange(.inBed).map(\.value)))
        #expect(model.periodSummary(.inBed)?.value == DurationText.hoursMinutes(minutes: inBedAverage))
        let efficiencyAverage = try #require(PeriodWindow.average(model.inRange(.efficiency).map(\.value)))
        #expect(model.periodSummary(.efficiency)?.value == "\(Formatters.whole(efficiencyAverage)) %")
    }
}
