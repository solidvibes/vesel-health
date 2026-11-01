import Foundation
import Testing
import VeselCore
import VeselWearable

struct ClearPlanTests {
    let today = day("2026-10-26")

    func rows(
        _ kind: FetchKind, from first: String, through last: String, storedAt: String, samples: Int = 10, deletedAt: String? = nil,
        earlierEmptyAt: String? = nil
    ) -> [LedgerEntry] {
        var rows: [LedgerEntry] = []
        var current = day(first)
        while current <= day(last) {
            rows.append(
                LedgerEntry(
                    day: current, kind: kind, storedAt: at(storedAt), sampleCount: samples, deletedFromBandAt: deletedAt.map(at),
                    earlierEmptyAt: earlierEmptyAt.map(at)))
            current = current.adding(days: 1)
        }
        return rows
    }

    @Test func nothingStoredClearsNothing() {
        #expect(ClearPlan.lastSafeDay(for: .sleep, ledger: [], today: today, timeZone: berlin) == nil)
    }

    @Test func dayStoredBeforeItEndedIsNotSafe() {
        // Stored at 23:00 Berlin on the 23rd: the 23rd wasn't over yet, so the band may still add to it.
        let ledger = rows(.sleep, from: "2026-10-20", through: "2026-10-23", storedAt: "2026-10-23T21:00:00Z")
        #expect(ClearPlan.lastSafeDay(for: .sleep, ledger: ledger, today: today, timeZone: berlin) == day("2026-10-22"))
    }

    @Test func emptyDaysReadEmptyTwiceCountAsStored() {
        let ledger =
            rows(.skinTemperature, from: "2026-10-20", through: "2026-10-21", storedAt: "2026-10-26T07:00:00Z")
            + rows(
                .skinTemperature, from: "2026-10-22", through: "2026-10-23", storedAt: "2026-10-26T07:00:00Z", samples: 0,
                earlierEmptyAt: "2026-10-25T07:00:00Z")
            + rows(.skinTemperature, from: "2026-10-24", through: "2026-10-24", storedAt: "2026-10-26T07:00:00Z")
        #expect(ClearPlan.lastSafeDay(for: .skinTemperature, ledger: ledger, today: today, timeZone: berlin) == day("2026-10-24"))
    }

    /// The SDK reports some failed reads as "no data": one empty read could be a failure, so it doesn't count yet.
    @Test func aDayReadEmptyOnceBlocks() {
        let ledger =
            rows(.skinTemperature, from: "2026-10-20", through: "2026-10-21", storedAt: "2026-10-26T07:00:00Z")
            + rows(.skinTemperature, from: "2026-10-22", through: "2026-10-22", storedAt: "2026-10-26T07:00:00Z", samples: 0)
            + rows(.skinTemperature, from: "2026-10-23", through: "2026-10-24", storedAt: "2026-10-26T07:00:00Z")
        #expect(ClearPlan.lastSafeDay(for: .skinTemperature, ledger: ledger, today: today, timeZone: berlin) == day("2026-10-21"))
    }

    @Test func anEarlierEmptyReadBeforeTheDayEndedDoesNotCount() {
        // Read empty at 08:00 Berlin on the 22nd (not worn yet that morning), then empty again after the day ended.
        let ledger = rows(
            .skinTemperature, from: "2026-10-22", through: "2026-10-22", storedAt: "2026-10-26T07:00:00Z", samples: 0, earlierEmptyAt: "2026-10-22T06:00:00Z")
        #expect(ClearPlan.lastSafeDay(for: .skinTemperature, ledger: ledger, today: today, timeZone: berlin) == nil)
    }

    @Test func emptyReadsLessThanAnHourApartDoNotSettle() {
        let close = rows(
            .skinTemperature, from: "2026-10-22", through: "2026-10-22", storedAt: "2026-10-26T07:10:00Z", samples: 0, earlierEmptyAt: "2026-10-26T07:00:00Z")
        #expect(ClearPlan.lastSafeDay(for: .skinTemperature, ledger: close, today: today, timeZone: berlin) == nil)
        let apart = rows(
            .skinTemperature, from: "2026-10-22", through: "2026-10-22", storedAt: "2026-10-26T08:20:00Z", samples: 0, earlierEmptyAt: "2026-10-26T07:20:00Z")
        #expect(ClearPlan.lastSafeDay(for: .skinTemperature, ledger: apart, today: today, timeZone: berlin) == day("2026-10-22"))
    }

    @Test func firstUnsettledDayIsTheEarliestNotYetStoredAfterTheLastClear() {
        let ledger =
            rows(.heartRate, from: "2026-10-10", through: "2026-10-15", storedAt: "2026-10-16T07:00:00Z", samples: 0, deletedAt: "2026-10-17T07:00:00Z")
            + rows(.heartRate, from: "2026-10-16", through: "2026-10-18", storedAt: "2026-10-26T07:00:00Z")
            + rows(.heartRate, from: "2026-10-19", through: "2026-10-19", storedAt: "2026-10-26T07:00:00Z", samples: 0)
            + rows(.heartRate, from: "2026-10-20", through: "2026-10-26", storedAt: "2026-10-26T07:00:00Z")
        #expect(ClearPlan.firstUnsettledDay(in: ledger, timeZone: berlin) == day("2026-10-19"))
        #expect(
            ClearPlan.firstUnsettledDay(in: rows(.heartRate, from: "2026-10-10", through: "2026-10-24", storedAt: "2026-10-26T07:00:00Z"), timeZone: berlin)
                == nil)
    }

    @Test func aMissingKindBlocksItsType() {
        let ledger =
            rows(.heartRate, from: "2026-10-20", through: "2026-10-24", storedAt: "2026-10-26T07:00:00Z")
            + rows(.ppi, from: "2026-10-20", through: "2026-10-21", storedAt: "2026-10-26T07:00:00Z")
            + rows(.ppi, from: "2026-10-23", through: "2026-10-24", storedAt: "2026-10-26T07:00:00Z")
        #expect(ClearPlan.lastSafeDay(for: .autoSample, ledger: ledger, today: today, timeZone: berlin) == day("2026-10-21"))
        #expect(
            ClearPlan.lastSafeDay(
                for: .autoSample, ledger: rows(.heartRate, from: "2026-10-20", through: "2026-10-24", storedAt: "2026-10-26T07:00:00Z"), today: today,
                timeZone: berlin) == nil)
    }

    @Test func gapAfterTheLastClearBlocks() {
        let ledger =
            rows(.sleep, from: "2026-10-10", through: "2026-10-15", storedAt: "2026-10-16T07:00:00Z", deletedAt: "2026-10-17T07:00:00Z")
            + rows(.sleep, from: "2026-10-17", through: "2026-10-24", storedAt: "2026-10-26T07:00:00Z")
        #expect(ClearPlan.lastSafeDay(for: .sleep, ledger: ledger, today: today, timeZone: berlin) == nil)
    }

    @Test func continuesAfterTheLastClear() {
        let ledger =
            rows(.sleep, from: "2026-10-10", through: "2026-10-15", storedAt: "2026-10-16T07:00:00Z", deletedAt: "2026-10-17T07:00:00Z")
            + rows(.sleep, from: "2026-10-16", through: "2026-10-24", storedAt: "2026-10-26T07:00:00Z")
        #expect(ClearPlan.lastSafeDay(for: .sleep, ledger: ledger, today: today, timeZone: berlin) == day("2026-10-24"))
    }

    @Test(arguments: [-10 * 3600, 0, 2 * 3600, 14 * 3600])
    func untilNamesTheDayInUTC(offset: Int) {
        let zone = TimeZone(secondsFromGMT: offset)!
        let clearedDay = DayKey(at("2026-10-24T23:30:00Z"), in: zone)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        let expected = String(format: "%04d%02d%02d", clearedDay.year, clearedDay.month, clearedDay.day)
        #expect(formatter.string(from: ClearPlan.until(clearedDay)) == expected)
    }
}
