import Foundation
import Testing
import VeselCore
@testable import VeselStorage

struct HourlyStepsObservationTests {
    let database: AppDatabase
    let day = DayKey("2026-10-27")!

    init() async throws {
        database = try AppDatabase.inMemory()
    }

    func store(_ day: DayKey, _ samples: [(String, Int)]) async throws {
        let list = samples.map { "{\"time\":\"\($0.0)\",\"steps\":\($0.1)}" }.joined(separator: ",")
        let payload = BandPayload(
            day: day, kind: .activitySamples,
            json: "{\"date\":\"\(day)\",\"samples\":[\(list)],\"met\":[{\"time\":\"\(day)T08:00:00+01:00\",\"met\":1.5}],\"activityClasses\":[]}",
            utcOffsetSeconds: 3600, sampleCount: samples.count + 1
        )
        try await database.save([payload], fetchedAt: at("2026-10-28T10:00:00Z"))
    }

    func read(_ day: DayKey) async throws -> HourlySteps {
        try await database.writer.read { try AppDatabase.hourlySteps($0, day: day) }
    }

    @Test func noRowIsEmpty() async throws {
        #expect(try await read(day).isEmpty)
    }

    @Test func anEmptyReadIsEmpty() async throws {
        try await database.save([.empty(day: day, kind: .activitySamples, utcOffsetSeconds: 3600)], fetchedAt: at("2026-10-28T10:00:00Z"))
        #expect(try await read(day).isEmpty)
    }

    @Test func minutesAreSummedIntoTheRightHour() async throws {
        try await store(
            day,
            [
                ("2026-10-27T07:59:00+01:00", 11), ("2026-10-27T08:00:00+01:00", 20), ("2026-10-27T08:01:00+01:00", 22), ("2026-10-27T17:30:00+01:00", 5),
            ])
        #expect(try await read(day).hours == [.init(hour: 7, steps: 11), .init(hour: 8, steps: 42), .init(hour: 17, steps: 5)])
    }

    @Test func aDayWithGapsOnlyHasBarsWhereThereWereSteps() async throws {
        try await store(
            day,
            [
                ("2026-10-27T00:00:00+01:00", 0), ("2026-10-27T09:10:00+01:00", 30), ("2026-10-27T09:11:00+01:00", 0), ("2026-10-27T21:45:00+01:00", 8),
            ])
        #expect(try await read(day).hours.map(\.hour) == [9, 21])
    }

    @Test func anotherDaysRowIsNotRead() async throws {
        try await store(day.adding(days: -1), [("2026-10-26T10:00:00+01:00", 50)])
        #expect(try await read(day).isEmpty)
    }
}
