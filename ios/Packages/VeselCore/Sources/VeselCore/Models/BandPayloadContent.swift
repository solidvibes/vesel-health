import Foundation

/// The typed rows inside one band payload. Activity samples have no typed table and stay raw.
public enum BandPayloadContent: Sendable, Equatable {
    case sleep(SleepNight)
    case nightlyRecharge(NightlyRecharge)
    case heartRates([HeartRateSample])
    case ppi([PPISession])
    case skinTemperatures([SkinTemperatureSample])
    case activity(ActivityDay)
    case none
}

public enum BandPayloadError: Error, Equatable {
    case unreadable(FetchKind, DayKey)
}

extension BandPayload {
    /// Reads the payload's band-local wall times as timestamps: each in the UTC offset it carries, else in `utcOffsetSeconds`.
    public func content() throws -> BandPayloadContent {
        if isEmpty { return .none }
        let wall = WallTime(day: day, utcOffsetSeconds: utcOffsetSeconds)
        let decoder = JSONDecoder()
        let data = Data(json.utf8)
        do {
            switch kind {
            case .sleep:
                let raw = try decoder.decode(RawSleep.self, from: data)
                return .sleep(
                    SleepNight(
                        night: raw.sleepResultDate.flatMap(DayKey.init) ?? day,
                        start: try wall.dateTime(raw.sleepStartTime),
                        end: try wall.dateTime(raw.sleepEndTime),
                        goalMinutes: raw.sleepGoalMinutes,
                        phases: raw.sleepWakePhases.map { SleepPhase(secondsFromStart: $0.secondsFromSleepStart, state: SleepState(band: $0.state)) }
                    ))
            case .nightlyRecharge:
                let raw = try decoder.decode(RawRecharge.self, from: data)
                return .nightlyRecharge(
                    NightlyRecharge(
                        night: raw.sleepResultDate.flatMap(DayKey.init) ?? day,
                        createdAt: try raw.createdTimestamp.map(wall.dateTime),
                        modifiedAt: try raw.modifiedTimestamp.map(wall.dateTime),
                        ansStatus: raw.ansStatus,
                        recoveryIndicator: raw.recoveryIndicator,
                        recoveryIndicatorSubLevel: raw.recoveryIndicatorSubLevel,
                        ansRate: raw.ansRate,
                        scoreRateObsolete: raw.scoreRateObsolete,
                        meanNightlyRecoveryRRI: raw.meanNightlyRecoveryRRI,
                        meanNightlyRecoveryRMSSD: raw.meanNightlyRecoveryRMSSD,
                        meanNightlyRecoveryRespirationInterval: raw.meanNightlyRecoveryRespirationInterval,
                        meanBaselineRRI: raw.meanBaselineRRI,
                        sdBaselineRRI: raw.sdBaselineRRI,
                        meanBaselineRMSSD: raw.meanBaselineRMSSD,
                        sdBaselineRMSSD: raw.sdBaselineRMSSD,
                        meanBaselineRespirationInterval: raw.meanBaselineRespirationInterval,
                        sdBaselineRespirationInterval: raw.sdBaselineRespirationInterval,
                        sleepTip: raw.sleepTip,
                        vitalityTip: raw.vitalityTip,
                        exerciseTip: raw.exerciseTip
                    ))
            case .heartRate:
                let raw = try decoder.decode(RawHeartRates.self, from: data)
                return .heartRates(
                    try raw.samples.map {
                        HeartRateSample(time: try wall.timeOfDay($0.time), bpm: $0.hr, trigger: HeartRateTrigger(band: $0.triggerType))
                    })
            case .ppi:
                let raw = try decoder.decode(RawPPI.self, from: data)
                return .ppi(
                    try raw.sessions.map { session in
                        let start = try wall.dateTime(session.startTime)
                        var elapsedMs = 0
                        let samples = session.samples.map { beat in
                            elapsedMs += beat.ppi
                            return PPISample(
                                time: start.addingTimeInterval(TimeInterval(elapsedMs) / 1000),
                                intervalMs: beat.ppi,
                                errorMs: beat.errorEstimate,
                                blocker: beat.blockerBit != 0,
                                skinContact: beat.skinContactSupported == 0 || beat.skinContactStatus != 0
                            )
                        }
                        return PPISession(
                            start: start, trigger: PPITrigger(band: session.trigger), utcOffsetSeconds: wall.offset(session.startTime), samples: samples)
                    })
            case .skinTemperature:
                let raw = try decoder.decode(RawSkinTemperatures.self, from: data)
                return .skinTemperatures(
                    try raw.samples.map {
                        SkinTemperatureSample(time: try wall.timeOfDay($0.time), celsius: $0.temperature)
                    })
            case .dailySummary:
                let raw = try decoder.decode(RawDailySummary.self, from: data)
                return .activity(
                    ActivityDay(
                        day: raw.date.flatMap(DayKey.init) ?? day,
                        steps: raw.steps,
                        activeSeconds: raw.activeDurationSeconds,
                        calories: raw.calories
                    ))
            case .activitySamples:
                return .none
            }
        } catch {
            throw BandPayloadError.unreadable(kind, day)
        }
    }
}

/// Band-local wall times ("2026-10-26T06:10:00", "06:10:00.250"), each in the UTC offset it carries ("06:10:00+01:00")
/// or else in the payload's one offset. Payloads stored before times carried offsets have none.
struct WallTime {
    let day: DayKey
    let utcOffsetSeconds: Int
    private let utc: Calendar

    init(day: DayKey, utcOffsetSeconds: Int) {
        self.day = day
        self.utcOffsetSeconds = utcOffsetSeconds
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        self.utc = utc
    }

    func dateTime(_ string: String) throws -> Date {
        let parts = string.split(separator: "T")
        guard parts.count == 2, let date = DayKey(String(parts[0])) else { throw BandPayloadError.unreadable(.sleep, day) }
        return try time(String(parts[1]), on: date)
    }

    func timeOfDay(_ string: String) throws -> Date {
        try time(string, on: day)
    }

    func offset(_ string: String) -> Int {
        split(string).offset
    }

    private func split(_ string: String) -> (clock: Substring, offset: Int) {
        let suffix = string.suffix(6)
        guard suffix.count == 6, let sign = suffix.first, sign == "+" || sign == "-",
            let hours = Int(suffix.dropFirst().prefix(2)), suffix.dropFirst(3).first == ":", let minutes = Int(suffix.suffix(2))
        else { return (string[...], utcOffsetSeconds) }
        return (string.dropLast(6), (sign == "-" ? -1 : 1) * (hours * 3600 + minutes * 60))
    }

    private func time(_ string: String, on date: DayKey) throws -> Date {
        let (clockTime, offset) = split(string)
        let fraction = clockTime.split(separator: ".", maxSplits: 1)
        let clock = fraction[0].split(separator: ":").compactMap { Int($0) }
        guard clock.count == 3 else { throw BandPayloadError.unreadable(.sleep, day) }
        let millis = fraction.count == 2 ? Int(fraction[1]) ?? 0 : 0
        let components = DateComponents(year: date.year, month: date.month, day: date.day, hour: clock[0], minute: clock[1], second: clock[2])
        guard let wall = utc.date(from: components) else { throw BandPayloadError.unreadable(.sleep, day) }
        return wall.addingTimeInterval(TimeInterval(millis) / 1000 - TimeInterval(offset))
    }
}

extension SleepState {
    init(band: String) {
        switch band {
        case "WAKE": self = .wake
        case "REM": self = .rem
        case "LIGHT", "NONREM12": self = .light
        case "DEEP", "NONREM3": self = .deep
        default: self = .unknown
        }
    }
}

extension HeartRateTrigger {
    init(band: String?) {
        switch band {
        case "TIMED", "timed": self = .timed
        case "HIGH_ACTIVITY", "highActivity": self = .highActivity
        case "LOW_ACTIVITY", "lowActivity": self = .lowActivity
        case "MANUAL", "manual": self = .manual
        default: self = .unknown
        }
    }
}

extension PPITrigger {
    init(band: String) {
        switch band {
        case "AUTOMATIC", "TRIGGER_TYPE_AUTOMATIC": self = .automatic
        case "MANUAL", "TRIGGER_TYPE_MANUAL": self = .manual
        default: self = .unknown
        }
    }
}

private struct RawSleep: Decodable {
    var sleepResultDate: String?
    var sleepStartTime: String
    var sleepEndTime: String
    var sleepGoalMinutes: Int?
    var sleepWakePhases: [Phase]

    struct Phase: Decodable {
        var secondsFromSleepStart: Int
        var state: String
    }
}

private struct RawRecharge: Decodable {
    var sleepResultDate: String?
    var createdTimestamp: String?
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

private struct RawHeartRates: Decodable {
    var samples: [Sample]

    struct Sample: Decodable {
        var time: String
        var hr: Int
        var triggerType: String?
    }
}

private struct RawPPI: Decodable {
    var sessions: [Session]

    struct Session: Decodable {
        var startTime: String
        var trigger: String
        var samples: [Beat]
    }

    struct Beat: Decodable {
        var ppi: Int
        var errorEstimate: Int
        var blockerBit: Int
        var skinContactStatus: Int
        /// 0 when the band didn't report contact for this beat: unknown is not "no contact".
        var skinContactSupported: Int
    }
}

private struct RawSkinTemperatures: Decodable {
    var samples: [Sample]

    struct Sample: Decodable {
        var time: String
        var temperature: Double
    }
}

private struct RawDailySummary: Decodable {
    var date: String?
    var steps: Int
    var activeDurationSeconds: Int
    var calories: ActivityDay.Calories
}
