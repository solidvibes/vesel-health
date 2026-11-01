import Foundation
@preconcurrency import PolarBleSdk
import VeselCore

/// Polar SDK results → one `BandPayload` per day, in the payload layout `BandPayload.content()` reads
/// (the same layout as the fake band's fixtures). Every value the SDK gives is kept; each band-local wall time is
/// written with the UTC offset it was in (`BandClock`). A number that isn't finite is left out: an optional one becomes nil,
/// a sample with one is dropped.
enum PolarMapping {
    static func sleep(_ result: PolarSleepData.PolarSleepAnalysisResult?, day: DayKey, zone: TimeZone) throws -> BandPayload {
        let offset = BandClock.noonOffset(day, in: zone)
        guard let result, let start = result.sleepStartTime, let end = result.sleepEndTime else {
            return .empty(day: day, kind: .sleep, utcOffsetSeconds: offset)
        }
        let wall = WallFormat(zone: zone)
        let phases = (result.sleepWakePhases ?? []).map {
            SleepPayload.Phase(secondsFromSleepStart: Int($0.secondsFromSleepStart ?? 0), state: $0.state?.rawValue ?? "UNKNOWN")
        }
        let payload = SleepPayload(
            sleepResultDate: result.sleepResultDate.flatMap(dayKey)?.description ?? day.description,
            sleepStartTime: wall.dateTime(start),
            sleepEndTime: wall.dateTime(end),
            lastModified: result.lastModified.map(wall.dateTime),
            sleepGoalMinutes: result.sleepGoalMinutes.map(Int.init),
            sleepWakePhases: phases,
            sleepCycles: (result.sleepCycles ?? []).compactMap { cycle in
                finite(cycle.sleepDepthStart ?? 0).map { SleepPayload.Cycle(secondsFromSleepStart: Int(cycle.secondsFromSleepStart ?? 0), sleepDepthStart: $0) }
            },
            sleepStartOffsetSeconds: result.sleepStartOffsetSeconds.map(Int.init),
            sleepEndOffsetSeconds: result.sleepEndOffsetSeconds.map(Int.init),
            alarmTime: result.alarmTime.map(wall.dateTime),
            snoozeTime: result.snoozeTime?.map(wall.dateTime),
            userSleepRating: result.userSleepRating?.rawValue,
            batteryRanOut: result.batteryRanOut,
            originalSleepStart: result.originalSleepRange?.startTime.map(wall.dateTime),
            originalSleepEnd: result.originalSleepRange?.endTime.map(wall.dateTime),
            sleepSkinTemperatureCelsius: result.sleepSkinTemperatureResult.flatMap { finite($0.sleepSkinTemperatureCelsius) },
            sleepSkinTemperatureDeviationFromBaseline: result.sleepSkinTemperatureResult.flatMap { finite($0.deviationFromBaseLine) }
        )
        return BandPayload(day: day, kind: .sleep, json: try encode(payload), utcOffsetSeconds: offset, sampleCount: max(phases.count, 1))
    }

    static func recharge(_ data: PolarNightlyRechargeData?, day: DayKey, zone: TimeZone) throws -> BandPayload {
        let offset = BandClock.noonOffset(day, in: zone)
        guard let data else { return .empty(day: day, kind: .nightlyRecharge, utcOffsetSeconds: offset) }
        let wall = WallFormat(zone: zone)
        return try recharge(
            RechargePayload(
                sleepResultDate: data.sleepResultDate.flatMap(dayKey)?.description ?? day.description,
                createdTimestamp: wall.dateTime(data.createdTimestamp),
                modifiedTimestamp: data.modifiedTimestamp.map(wall.dateTime),
                ansStatus: data.ansStatus.map(Double.init),
                recoveryIndicator: data.recoveryIndicator,
                recoveryIndicatorSubLevel: data.recoveryIndicatorSubLevel,
                ansRate: data.ansRate,
                scoreRateObsolete: data.scoreRateObsolete,
                meanNightlyRecoveryRRI: data.meanNightlyRecoveryRRI,
                meanNightlyRecoveryRMSSD: data.meanNightlyRecoveryRMSSD,
                meanNightlyRecoveryRespirationInterval: data.meanNightlyRecoveryRespirationInterval,
                meanBaselineRRI: data.meanBaselineRRI,
                sdBaselineRRI: data.sdBaselineRRI,
                meanBaselineRMSSD: data.meanBaselineRMSSD,
                sdBaselineRMSSD: data.sdBaselineRMSSD,
                meanBaselineRespirationInterval: data.meanBaselineRespirationInterval,
                sdBaselineRespirationInterval: data.sdBaselineRespirationInterval,
                sleepTip: data.sleepTip,
                vitalityTip: data.vitalityTip,
                exerciseTip: data.exerciseTip
            ), day: day, utcOffsetSeconds: offset)
    }

    /// Split out because the SDK's `PolarNightlyRechargeData` has no public initializer, so tests start here.
    static func recharge(_ payload: RechargePayload, day: DayKey, utcOffsetSeconds offset: Int) throws -> BandPayload {
        var payload = payload
        payload.ansStatus = payload.ansStatus.flatMap(finite)
        return BandPayload(day: day, kind: .nightlyRecharge, json: try encode(payload), utcOffsetSeconds: offset, sampleCount: 1)
    }

    /// A 24/7 sample can carry several heart rates, one per second from its time. `results` are every file the
    /// band has for the day; all are kept, since clearing removes them all.
    static func heartRates(_ results: [Polar247HrSamplesData], day: DayKey, zone: TimeZone) throws -> BandPayload {
        let offset = BandClock.noonOffset(day, in: zone)
        let readings = results.flatMap(\.samples).flatMap { sample in
            let base = seconds(sample.time)
            return sample.hrSamples.enumerated().map { index, bpm in (time: base + index, bpm: Int(bpm), trigger: sample.triggerType?.rawValue) }
        }
        let offsets = BandClock(day: day, zone: zone).offsets(readings.map(\.time))
        let samples = zip(readings, offsets).map { reading, offset in
            HeartRatePayload.Sample(time: clockTime(reading.time) + BandClock.suffix(offset), hr: reading.bpm, triggerType: reading.trigger)
        }
        guard !samples.isEmpty else { return .empty(day: day, kind: .heartRate, utcOffsetSeconds: offset) }
        return BandPayload(
            day: day, kind: .heartRate, json: try encode(HeartRatePayload(date: day.description, samples: samples)), utcOffsetSeconds: offset,
            sampleCount: samples.count)
    }

    /// Flags stay with each beat: moving or an offline gap marks it as blocked; analysis drops those.
    /// A beat with no status gets `skinContactSupported` 0: contact unknown, not "no contact".
    static func ppi(_ results: [Polar247PPiSamplesData], day: DayKey, zone: TimeZone) throws -> BandPayload {
        let offset = BandClock.noonOffset(day, in: zone)
        let recorded = results.flatMap(\.samples)
        let starts = recorded.map { $0.startTime ?? "00:00:00" }
        let offsets = BandClock(day: day, zone: zone).offsets(starts.map { seconds(clock: $0) })
        let sessions = zip(recorded, zip(starts, offsets)).map { session, timing in
            let (start, startOffset) = timing
            let values = session.ppiValueList ?? []
            let errors = session.ppiErrorEstimateList ?? []
            let statuses = session.statusList ?? []
            let beats = values.indices.map { index in
                let status = index < statuses.count ? statuses[index] : nil
                let moving = status?.movement == .MOVING_DETECTED
                let offline = status?.intervalStatus == .INTERVAL_DENOTES_OFFLINE_PERIOD
                return PPIPayload.Beat(
                    ppi: Int(values[index]),
                    errorEstimate: index < errors.count ? Int(errors[index]) : 0,
                    blockerBit: moving || offline ? 1 : 0,
                    skinContactStatus: status?.skinContact == .SKIN_CONTACT_DETECTED ? 1 : 0,
                    skinContactSupported: status == nil ? 0 : 1,
                    movement: status?.movement.rawValue,
                    intervalStatus: status?.intervalStatus.rawValue
                )
            }
            return PPIPayload.Session(
                startTime: "\(day)T\(start)\(BandClock.suffix(startOffset))", trigger: session.triggerType?.rawValue ?? "TRIGGER_TYPE_UNDEFINED", samples: beats
            )
        }
        let count = sessions.reduce(0) { $0 + $1.samples.count }
        guard count > 0 else { return .empty(day: day, kind: .ppi, utcOffsetSeconds: offset) }
        return BandPayload(
            day: day, kind: .ppi, json: try encode(PPIPayload(date: day.description, sessions: sessions)), utcOffsetSeconds: offset, sampleCount: count)
    }

    /// Sample times are milliseconds from the start of the band's day.
    static func skinTemperature(_ result: PolarSkinTemperatureData.PolarSkinTemperatureResult?, day: DayKey, zone: TimeZone) throws -> BandPayload {
        let offset = BandClock.noonOffset(day, in: zone)
        let recorded = (result?.skinTemperatureList ?? []).filter { ($0.temperature ?? 0).isFinite }
        let deltas = recorded.map { Int($0.recordingTimeDeltaMs ?? 0) }
        let offsets = BandClock(day: day, zone: zone).offsets(deltas.map { $0 / 1000 })
        let samples = zip(recorded, zip(deltas, offsets)).map { sample, timing in
            let (deltaMs, offset) = timing
            return SkinTemperaturePayload.Sample(
                time: clockTime(deltaMs / 1000, millis: deltaMs % 1000) + BandClock.suffix(offset),
                temperature: Double(sample.temperature ?? 0),
                recordingTimeDeltaMs: deltaMs
            )
        }
        guard !samples.isEmpty else { return .empty(day: day, kind: .skinTemperature, utcOffsetSeconds: offset) }
        let payload = SkinTemperaturePayload(
            date: day.description,
            sensorLocation: result?.sensorLocation?.rawValue,
            measurementType: result?.measurementType?.rawValue,
            samples: samples
        )
        return BandPayload(day: day, kind: .skinTemperature, json: try encode(payload), utcOffsetSeconds: offset, sampleCount: samples.count)
    }

    static func activitySamples(_ data: PolarActivityDayData?, day: DayKey, zone: TimeZone) throws -> BandPayload {
        let offset = BandClock.noonOffset(day, in: zone)
        let wall = WallFormat(zone: zone)
        var steps: [ActivityPayload.Steps] = []
        var met: [ActivityPayload.Met] = []
        var classes: [ActivityPayload.ActivityClass] = []
        for activity in data?.polarActivityDataList ?? [] {
            guard let samples = activity.samples else { continue }
            for (index, value) in (samples.stepSamples ?? []).enumerated() {
                let time = samples.startTime.addingTimeInterval(TimeInterval(index * samples.stepRecordingInterval))
                steps.append(.init(time: wall.dateTime(time), steps: Int(value)))
            }
            for (index, value) in (samples.metSamples ?? []).enumerated() where value.isFinite {
                let time = samples.startTime.addingTimeInterval(TimeInterval(index * samples.metRecordingInterval))
                met.append(.init(time: wall.dateTime(time), met: Double(value)))
            }
            classes += samples.activityInfoList.filter(\.factor.isFinite).map {
                .init(time: wall.dateTime($0.timeStamp), activityClass: $0.activityClass.rawValue, factor: Double($0.factor))
            }
        }
        let count = steps.count + met.count + classes.count
        guard count > 0 else { return .empty(day: day, kind: .activitySamples, utcOffsetSeconds: offset) }
        let payload = ActivityPayload(date: day.description, samples: steps, met: met, activityClasses: classes)
        return BandPayload(day: day, kind: .activitySamples, json: try encode(payload), utcOffsetSeconds: offset, sampleCount: count)
    }

    /// Active time is the light, moderate and vigorous time; total calories are BMR plus activity, as Polar shows them.
    static func dailySummary(_ summary: PolarDailySummary?, day: DayKey, zone: TimeZone) throws -> BandPayload {
        let offset = BandClock.noonOffset(day, in: zone)
        guard let summary else { return .empty(day: day, kind: .dailySummary, utcOffsetSeconds: offset) }
        let times = summary.activityClassTimes
        let active = [
            times.timeLightActivity, times.timeContinuousModerateActivity, times.timeIntermittentModerateActivity,
            times.timeContinuousVigorousActivity, times.timeIntermittentVigorousActivity,
        ].reduce(0) { $0 + seconds($1) }
        let bmr = Int(summary.bmrCalories)
        let activity = Int(summary.activityCalories)
        let payload = DailySummaryPayload(
            date: day.description,
            steps: Int(summary.steps),
            activeDurationSeconds: active,
            calories: .init(bmr: bmr, activity: activity, total: bmr + activity),
            trainingCalories: Int(summary.trainingCalories),
            activityDistanceMeters: Double(summary.activityDistance),
            activityClassSeconds: [
                "nonWear": seconds(times.timeNonWear),
                "sleep": seconds(times.timeSleep),
                "sedentary": seconds(times.timeSedentary),
                "light": seconds(times.timeLightActivity),
                "continuousModerate": seconds(times.timeContinuousModerateActivity),
                "intermittentModerate": seconds(times.timeIntermittentModerateActivity),
                "continuousVigorous": seconds(times.timeContinuousVigorousActivity),
                "intermittentVigorous": seconds(times.timeIntermittentVigorousActivity),
            ],
            dailyBalanceFeedback: summary.dailyBalanceFeedback.rawValue,
            readinessForSpeedAndStrengthTraining: summary.readinessForSpeedAndStrengthTraining.rawValue
        )
        return BandPayload(day: day, kind: .dailySummary, json: try encode(payload), utcOffsetSeconds: offset, sampleCount: 1)
    }

    /// Minutes left in the band's inactivity alert (`PbPFtpInactivityAlert.countdown`, field 1): 0 means it fired, more is
    /// the warning before it. Nil when the bytes aren't a readable message.
    static func inactivityCountdown(_ parameters: Data) -> Int? {
        var bytes = parameters[...]
        var countdown = 0
        while !bytes.isEmpty {
            guard let key = varint(&bytes) else { return nil }
            switch key & 7 {
            case 0:
                guard let value = varint(&bytes) else { return nil }
                if key >> 3 == 1 { countdown = Int(truncatingIfNeeded: value) }
            case 1, 5:
                let size = key & 7 == 1 ? 8 : 4
                guard bytes.count >= size else { return nil }
                bytes = bytes.dropFirst(size)
            case 2:
                guard let length = varint(&bytes), length <= UInt64(bytes.count) else { return nil }
                bytes = bytes.dropFirst(Int(length))
            default:
                return nil
            }
        }
        return countdown
    }

    private static func varint(_ bytes: inout Data.SubSequence) -> UInt64? {
        var value: UInt64 = 0
        for shift in stride(from: 0, to: 64, by: 7) {
            guard let byte = bytes.popFirst() else { return nil }
            value |= UInt64(byte & 0x7F) << UInt64(shift)
            if byte & 0x80 == 0 { return value }
        }
        return nil
    }

    static func dayKey(_ components: DateComponents) -> DayKey? {
        guard let year = components.year, let month = components.month, let day = components.day else { return nil }
        return DayKey(year: year, month: month, day: day)
    }

    private static func seconds(_ time: DateComponents) -> Int {
        (time.hour ?? 0) * 3600 + (time.minute ?? 0) * 60 + (time.second ?? 0)
    }

    /// "03:00:00.250" → 10800.
    private static func seconds(clock: String) -> Int {
        let parts = clock.prefix(8).split(separator: ":").compactMap { Int($0) }
        return parts.count == 3 ? parts[0] * 3600 + parts[1] * 60 + parts[2] : 0
    }

    private static func seconds(_ time: PolarActiveTime) -> Int {
        time.hours * 3600 + time.minutes * 60 + time.seconds
    }

    private static func clockTime(_ seconds: Int, millis: Int = 0) -> String {
        let clock = String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        return millis == 0 ? clock : clock + String(format: ".%03d", millis)
    }

    private static func finite(_ value: some BinaryFloatingPoint) -> Double? {
        value.isFinite ? Double(value) : nil
    }

    /// Throws on a number that isn't finite; the day then counts as a failed read.
    private static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}

/// Formats an instant as wall time in the zone's offset at that instant: `2026-10-26T06:10:00(.250)+01:00`.
struct WallFormat {
    let zone: TimeZone
    let utc: Calendar

    init(zone: TimeZone) {
        self.zone = zone
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        self.utc = utc
    }

    func dateTime(_ date: Date) -> String {
        let offset = zone.secondsFromGMT(for: date)
        let c = utc.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date.addingTimeInterval(TimeInterval(offset)))
        let base = String(format: "%04d-%02d-%02dT%02d:%02d:%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
        let millis = Int((Double(c.nanosecond ?? 0) / 1_000_000).rounded())
        return (millis == 0 || millis == 1000 ? base : base + String(format: ".%03d", millis)) + BandClock.suffix(offset)
    }
}

struct SleepPayload: Encodable {
    var sleepResultDate: String
    var sleepStartTime: String
    var sleepEndTime: String
    var lastModified: String?
    var sleepGoalMinutes: Int?
    var sleepWakePhases: [Phase]
    var sleepCycles: [Cycle]
    var sleepStartOffsetSeconds: Int?
    var sleepEndOffsetSeconds: Int?
    var alarmTime: String?
    var snoozeTime: [String]?
    var userSleepRating: Int?
    var batteryRanOut: Bool?
    var originalSleepStart: String?
    var originalSleepEnd: String?
    var sleepSkinTemperatureCelsius: Double?
    var sleepSkinTemperatureDeviationFromBaseline: Double?

    struct Phase: Encodable {
        var secondsFromSleepStart: Int
        var state: String
    }

    struct Cycle: Encodable {
        var secondsFromSleepStart: Int
        var sleepDepthStart: Double
    }
}

struct RechargePayload: Encodable {
    var sleepResultDate: String
    var createdTimestamp: String
    var modifiedTimestamp: String?
    var ansStatus: Double?
    var recoveryIndicator: Int?
    var recoveryIndicatorSubLevel: Int?
    var ansRate: Int?
    var scoreRateObsolete: Int?
    var meanNightlyRecoveryRRI: Int?
    var meanNightlyRecoveryRMSSD: Int?
    var meanNightlyRecoveryRespirationInterval: Int?
    var meanBaselineRRI: Int?
    var sdBaselineRRI: Int?
    var meanBaselineRMSSD: Int?
    var sdBaselineRMSSD: Int?
    var meanBaselineRespirationInterval: Int?
    var sdBaselineRespirationInterval: Int?
    var sleepTip: String?
    var vitalityTip: String?
    var exerciseTip: String?
}

struct HeartRatePayload: Encodable {
    var date: String
    var samples: [Sample]

    struct Sample: Encodable {
        var time: String
        var hr: Int
        var triggerType: String?
    }
}

struct PPIPayload: Encodable {
    var date: String
    var sessions: [Session]

    struct Session: Encodable {
        var startTime: String
        var trigger: String
        var samples: [Beat]
    }

    struct Beat: Encodable {
        var ppi: Int
        var errorEstimate: Int
        var blockerBit: Int
        var skinContactStatus: Int
        var skinContactSupported: Int
        var movement: String?
        var intervalStatus: String?
    }
}

struct SkinTemperaturePayload: Encodable {
    var date: String
    var sensorLocation: String?
    var measurementType: String?
    var samples: [Sample]

    struct Sample: Encodable {
        var time: String
        var temperature: Double
        var recordingTimeDeltaMs: Int
    }
}

struct ActivityPayload: Encodable {
    var date: String
    var samples: [Steps]
    var met: [Met]
    var activityClasses: [ActivityClass]

    struct Steps: Encodable {
        var time: String
        var steps: Int
    }

    struct Met: Encodable {
        var time: String
        var met: Double
    }

    struct ActivityClass: Encodable {
        var time: String
        var activityClass: String
        var factor: Double
    }
}

struct DailySummaryPayload: Encodable {
    var date: String
    var steps: Int
    var activeDurationSeconds: Int
    var calories: ActivityDay.Calories
    var trainingCalories: Int
    var activityDistanceMeters: Double
    var activityClassSeconds: [String: Int]
    var dailyBalanceFeedback: String
    var readinessForSpeedAndStrengthTraining: String
}
