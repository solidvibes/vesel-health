import Foundation
import GRDB
import VeselCore

extension AppDatabase {
    /// The shown day's steps by hour, from the per-minute step samples kept as they came in `raw_export`. Reads only that day's
    /// `samples` and decodes them on the reader's queue; no row means none.
    public func observeHourlySteps(day: DayKey) -> some AsyncSequence<HourlySteps, any Error> {
        ValueObservation.tracking { db in try Self.hourlySteps(db, day: day) }.removeDuplicates().values(in: writer)
    }

    static func hourlySteps(_ db: Database, day: DayKey) throws -> HourlySteps {
        let text = try String.fetchOne(
            db,
            sql: """
                SELECT json_extract(json, '$.samples') FROM raw_export WHERE day = ? AND kind = ?
                """, arguments: [day.description, FetchKind.activitySamples.rawValue])
        let samples = text.flatMap { try? JSONDecoder().decode([HourlySteps.Sample].self, from: Data($0.utf8)) }
        return HourlySteps(day: day, samples: samples ?? [])
    }
}
