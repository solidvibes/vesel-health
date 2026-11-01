import Foundation
import GRDB
import VeselCore

struct HeartRateSampleRecord: UpsertRecord {
    static let databaseTableName = "hr_sample"
    static let keyColumns: Set<String> = ["ts"]

    var ts: Int64
    var bpm: Int
    var trigger: String

    init(_ sample: HeartRateSample) {
        ts = sample.time.unixSeconds
        bpm = sample.bpm
        trigger = sample.trigger.rawValue
    }

    var model: HeartRateSample {
        HeartRateSample(time: Date(unixSeconds: ts), bpm: bpm, trigger: HeartRateTrigger(rawValue: trigger) ?? .unknown)
    }
}

struct PPISessionRecord: UpsertRecord {
    static let databaseTableName = "ppi_session"
    static let keyColumns: Set<String> = ["start_ts"]

    var day: String
    var startTs: Int64
    var trigger: String
    var utcOffsetSeconds: Int

    init(_ session: PPISession) {
        day = DayKey(session.start, in: TimeZone(secondsFromGMT: session.utcOffsetSeconds)!).description
        startTs = session.start.unixSeconds
        trigger = session.trigger.rawValue
        utcOffsetSeconds = session.utcOffsetSeconds
    }
}

struct PPISampleRecord: UpsertRecord {
    static let databaseTableName = "ppi_sample"
    static let keyColumns: Set<String> = ["ts_ms"]

    var tsMs: Int64
    var sessionId: Int64
    var intervalMs: Int
    var errorMs: Int
    var blocker: Bool
    var skinContact: Bool

    init(_ sample: PPISample, sessionId: Int64) {
        tsMs = sample.time.unixMilliseconds
        self.sessionId = sessionId
        intervalMs = sample.intervalMs
        errorMs = sample.errorMs
        blocker = sample.blocker
        skinContact = sample.skinContact
    }
}

struct SkinTemperatureSampleRecord: UpsertRecord {
    static let databaseTableName = "skin_temp_sample"
    static let keyColumns: Set<String> = ["ts"]

    var ts: Int64
    var celsius: Double

    init(_ sample: SkinTemperatureSample) {
        ts = sample.time.unixSeconds
        celsius = sample.celsius
    }
}

struct ActivityDayRecord: UpsertRecord {
    static let databaseTableName = "activity_day"
    static let keyColumns: Set<String> = ["day"]

    var day: String
    var steps: Int
    var activeSeconds: Int
    var caloriesJson: String

    init(_ activity: ActivityDay) throws {
        day = activity.day.description
        steps = activity.steps
        activeSeconds = activity.activeSeconds
        caloriesJson = try StoredJSON.encode(activity.calories)
    }
}
