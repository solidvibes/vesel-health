import Foundation
import GRDB
import VeselCore

struct SleepNightRecord: UpsertRecord {
    static let databaseTableName = "sleep_night"
    static let keyColumns: Set<String> = ["night"]

    var night: String
    var startAt: Int64
    var endAt: Int64
    var goalMinutes: Int?
    var phasesJson: String
    var rawJson: String

    init(_ sleep: SleepNight, rawJSON: String) throws {
        night = sleep.night.description
        startAt = sleep.start.unixSeconds
        endAt = sleep.end.unixSeconds
        goalMinutes = sleep.goalMinutes
        phasesJson = try StoredJSON.encode(sleep.phases)
        rawJson = rawJSON
    }

    func model() throws -> SleepNight {
        SleepNight(
            night: try DayKey(stored: night),
            start: Date(unixSeconds: startAt),
            end: Date(unixSeconds: endAt),
            goalMinutes: goalMinutes,
            phases: try StoredJSON.decode([SleepPhase].self, from: phasesJson)
        )
    }
}
