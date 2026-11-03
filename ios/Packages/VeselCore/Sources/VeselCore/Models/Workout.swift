import Foundation

/// The sports Vesel names. Anything else is a "Workout".
public enum WorkoutSport: String, CaseIterable, Sendable {
    case running, cycling, swimming, strength

    /// Ties between guesses go in this order.
    public static let guessOrder: [WorkoutSport] = [.cycling, .running, .swimming, .strength]

    /// The Loop's sport id, for the ids the Polar SDK names. Others are added only after a check on the real Loop.
    public init?(bandSportId: Int) {
        switch bandSportId {
        case 1: self = .running
        case 2: self = .cycling
        default: return nil
        }
    }

    /// The sport's name in Your sports and the sport sheet.
    public var name: String {
        switch self {
        case .running: "Running"
        case .cycling: "Cycling"
        case .swimming: "Swimming"
        case .strength: "Strength"
        }
    }

    /// The sport in a sentence: "after yesterday's ride", "during a run".
    public var noun: String {
        switch self {
        case .running: "run"
        case .cycling: "ride"
        case .swimming: "swim"
        case .strength: "strength session"
        }
    }
}

/// One workout the Loop recorded, keyed by its folder on the band ("20261103/071000"), which never changes for that workout.
public struct Workout: Sendable, Equatable {
    public var session: String
    public var start: Date
    public var end: Date
    public var utcOffsetSeconds: Int
    public var bandSportId: Int?
    public var durationSeconds: Int
    public var calories: Int?
    public var cardioLoad: Double?
    /// Polar's `cardioLoadInterpretation`, 1–5, as given.
    public var cardioLoadRating: Int?
    /// The older load number; shown only without a cardio load.
    public var trainingLoad: Double?
    public var averageHeartRate: Int?
    public var maxHeartRate: Int?
    /// A typed copy of the Loop's heart rate during the workout, for drawing; the band's file stays as it came.
    public var heartRates: WorkoutHeartRates?
    /// The total size of the workout's files on the Loop; a change means the band's copy changed.
    public var fileSize: Int64
    /// Files that arrived but didn't parse.
    public var unreadableFiles: [String]

    public init(
        session: String, start: Date, end: Date, utcOffsetSeconds: Int, bandSportId: Int?, durationSeconds: Int, calories: Int?,
        cardioLoad: Double?, cardioLoadRating: Int?, trainingLoad: Double?, averageHeartRate: Int?, maxHeartRate: Int?,
        heartRates: WorkoutHeartRates?, fileSize: Int64, unreadableFiles: [String]
    ) {
        self.session = session
        self.start = start
        self.end = end
        self.utcOffsetSeconds = utcOffsetSeconds
        self.bandSportId = bandSportId
        self.durationSeconds = durationSeconds
        self.calories = calories
        self.cardioLoad = cardioLoad
        self.cardioLoadRating = cardioLoadRating
        self.trainingLoad = trainingLoad
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.heartRates = heartRates
        self.fileSize = fileSize
        self.unreadableFiles = unreadableFiles
    }

    /// A workout belongs to the local day it started on.
    public var day: DayKey {
        DayKey(start, in: TimeZone(secondsFromGMT: utcOffsetSeconds) ?? .gmt)
    }

    public var interval: DateInterval { DateInterval(start: start, end: max(start, end)) }

    /// "42 min", "1 h 15 min".
    public var durationText: String {
        let (hours, minutes) = hoursAndMinutes
        if hours == 0 { return "\(minutes) min" }
        return minutes == 0 ? "\(hours) h" : "\(hours) h \(minutes) min"
    }

    /// For VoiceOver: "42 minutes", "1 hour 15 minutes".
    public var spokenDuration: String {
        let (hours, minutes) = hoursAndMinutes
        let minuteText = "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
        guard hours > 0 else { return minuteText }
        let hourText = "\(hours) \(hours == 1 ? "hour" : "hours")"
        return minutes == 0 ? hourText : "\(hourText) \(minuteText)"
    }

    private var hoursAndMinutes: (Int, Int) {
        let total = Int((Double(durationSeconds) / 60).rounded())
        return (total / 60, total % 60)
    }
}

/// Heart rate during a workout, one value every `intervalMs`.
public struct WorkoutHeartRates: Sendable, Equatable, Codable {
    public var intervalMs: Int
    public var bpm: [Int]

    public init(intervalMs: Int, bpm: [Int]) {
        self.intervalMs = intervalMs
        self.bpm = bpm
    }
}

/// One file of a workout, as the Polar SDK handed it over.
public struct WorkoutFile: Sendable, Equatable {
    /// "TSESS", "00/BASE", "00/SAMPLES", …
    public var name: String
    public var data: Data

    public init(name: String, data: Data) {
        self.name = name
        self.data = data
    }
}

/// A workout as read off the band: its typed row and every file as it came.
public struct BandWorkout: Sendable, Equatable {
    public var workout: Workout
    public var files: [WorkoutFile]

    public init(workout: Workout, files: [WorkoutFile]) {
        self.workout = workout
        self.files = files
    }
}

/// The Loop's automatic training detection.
public struct WorkoutDetection: Sendable, Equatable, Codable {
    public var isOn: Bool
    /// 0–100; higher notices more easily.
    public var sensitivity: Int
    public var minimumMinutes: Int

    public init(isOn: Bool, sensitivity: Int, minimumMinutes: Int) {
        self.isOn = isOn
        self.sensitivity = sensitivity
        self.minimumMinutes = minimumMinutes
    }

    /// What the Polar SDK writes when the Loop has no values of its own.
    public static let sdkFallback = WorkoutDetection(isOn: true, sensitivity: 50, minimumMinutes: 10)
}

/// The owner's fix to a workout: another sport, or not a workout at all. A band read never changes it.
public struct WorkoutChoice: Sendable, Equatable {
    public var session: String
    public var sport: WorkoutSport?
    public var hidden: Bool
    public var chosenAt: Date

    public init(session: String, sport: WorkoutSport?, hidden: Bool, chosenAt: Date) {
        self.session = session
        self.sport = sport
        self.hidden = hidden
        self.chosenAt = chosenAt
    }
}

/// The phone's route during one workout the Loop noticed, from the Loop's start notice to its end notice. `end` is nil while
/// it is still being recorded (or when the recording stopped without one). Joined to the band's workout by time.
public struct RecordedRoute: Sendable, Equatable {
    public var start: Date
    public var end: Date?
    public var points: [RoutePoint]

    public init(start: Date, end: Date?, points: [RoutePoint]) {
        self.start = start
        self.end = end
        self.points = points
    }

    /// From the start to its end, or to its last point while it has no end.
    public var interval: DateInterval {
        DateInterval(start: start, end: max(start, end ?? points.last?.time ?? start))
    }
}

/// A workout's time and its word, for drawing on a chart.
public struct WorkoutSpan: Sendable, Equatable {
    public var range: ClosedRange<Date>
    public var word: String

    public init(range: ClosedRange<Date>, word: String) {
        self.range = range
        self.word = word
    }
}
