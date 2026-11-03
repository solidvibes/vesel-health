// Writes the fake band's synthetic fixtures. Deterministic: the same seed always gives the same files.
// Run from the repo root: swift ios/Tools/make-fixtures.swift
// Synthetic data only. Real band recordings go in the gitignored ios/LocalFixtures/, never here.
import Foundation

struct SplitMix64 {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }

    mutating func double(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + Double(next() >> 11) / Double(1 << 53) * (range.upperBound - range.lowerBound)
    }
}

struct Entry: Encodable {
    var day: String
    var utcOffsetSeconds: Int
    var sampleCount: Int
    var payload: [String: AnyEncodable]
}

struct AnyEncodable: Encodable {
    let encodeValue: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T) { encodeValue = value.encode }
    func encode(to encoder: Encoder) throws { try encodeValue(encoder) }
}

func round1(_ value: Double) -> Double { (value * 10).rounded() / 10 }

let berlin = TimeZone(identifier: "Europe/Berlin")!
var utc = Calendar(identifier: .gregorian)
utc.timeZone = TimeZone(identifier: "UTC")!
let firstDay = utc.date(from: DateComponents(year: 2026, month: 9, day: 26))!

func dayString(_ date: Date) -> String {
    let c = utc.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
}

/// The fake band follows Berlin time, like a band synced right at each clock change; a repeated hour is its first pass.
func offsetSuffix(_ dayStart: Date, plusSeconds seconds: Int) -> String {
    let wall = dayStart.addingTimeInterval(TimeInterval(seconds))
    let around = [berlin.secondsFromGMT(for: wall.addingTimeInterval(-86400)), berlin.secondsFromGMT(for: wall.addingTimeInterval(86400))]
    let offset = around.filter { berlin.secondsFromGMT(for: wall.addingTimeInterval(TimeInterval(-$0))) == $0 }.max() ?? around[0]
    return String(format: "+%02d:%02d", offset / 3600, offset / 60 % 60)
}

func wallTime(_ dayStart: Date, plusSeconds seconds: Int) -> String {
    let c = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: dayStart.addingTimeInterval(TimeInterval(seconds)))
    return String(format: "%04d-%02d-%02dT%02d:%02d:%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
        + offsetSuffix(dayStart, plusSeconds: seconds)
}

var rng = SplitMix64(state: 20261026)
// Daytime beat-to-beat sessions have their own generator, so adding them never changes the other fixtures.
var daytimeRng = SplitMix64(state: 20261027)
// Skin temperature outside the old hourly readings has its own generator too.
var skinRng = SplitMix64(state: 20261028)
// Seconds per activity class in the daily summary have their own generator too.
var classRng = SplitMix64(state: 20261030)
// The last three days' extra daytime sessions, every 5 minutes, have their own generator too.
var denseRng = SplitMix64(state: 20261029)
var sleep: [Entry] = [], recharge: [Entry] = [], heartRate: [Entry] = [], ppi: [Entry] = []
var skinTemperature: [Entry] = [], activitySamples: [Entry] = [], dailySummary: [Entry] = []

enum DaytimeStress { case calm, moderate, stressed }

/// Day 0 is 2026-09-26, day 29 is 2026-10-25. Day 29 has a stressed afternoon; a few earlier days have rougher stretches.
func stressLevel(dayIndex: Int, hour: Int) -> DaytimeStress {
    switch (dayIndex, hour) {
    case (29, 13...16): .stressed
    case (29, 12): .moderate
    case (28, 10...11): .stressed
    case (28, 15): .moderate
    case (27, 16): .stressed
    case (27, 14...15): .moderate
    case (25, 9...10): .moderate
    case (22, 11...13): .stressed
    case (19, 14), (16, 10), (12, 15), (8, 11): .moderate
    default: .calm
    }
}

for index in 0..<30 {
    let dayStart = utc.date(byAdding: .day, value: index, to: firstDay)!
    let day = dayString(dayStart)
    let offset = berlin.secondsFromGMT(for: dayStart.addingTimeInterval(12 * 3600))

    // Sleep: starts the evening before (local wall time), ends this morning.
    let sleepStart = -rng.int(30...90) * 60
    let duration = rng.int(410...490) * 60
    var phases: [[String: AnyEncodable]] = []
    var t = 0
    while t < duration {
        let cycle: [(String, ClosedRange<Int>)] = [("LIGHT", 20...40), ("DEEP", t < duration / 2 ? 20...35 : 5...15), ("LIGHT", 10...20), ("REM", 10...25)]
        for (state, minutes) in cycle where t < duration {
            phases.append(["secondsFromSleepStart": AnyEncodable(t), "state": AnyEncodable(state)])
            t += rng.int(minutes) * 60
        }
        if rng.int(0...3) == 0, t < duration {
            phases.append(["secondsFromSleepStart": AnyEncodable(t), "state": AnyEncodable("WAKE")])
            t += rng.int(2...6) * 60
        }
    }
    sleep.append(
        Entry(
            day: day, utcOffsetSeconds: offset, sampleCount: phases.count,
            payload: [
                "sleepResultDate": AnyEncodable(day),
                "sleepStartTime": AnyEncodable(wallTime(dayStart, plusSeconds: sleepStart)),
                "sleepEndTime": AnyEncodable(wallTime(dayStart, plusSeconds: sleepStart + duration)),
                "sleepGoalMinutes": AnyEncodable(480),
                "sleepWakePhases": AnyEncodable(phases),
            ]))

    let rmssd = rng.int(36...58)
    recharge.append(
        Entry(
            day: day, utcOffsetSeconds: offset, sampleCount: 1,
            payload: [
                "sleepResultDate": AnyEncodable(day),
                "createdTimestamp": AnyEncodable(wallTime(dayStart, plusSeconds: sleepStart + duration + 600)),
                "ansStatus": AnyEncodable(round1(rng.double(-3...6))),
                "recoveryIndicator": AnyEncodable(rng.int(2...5)),
                "recoveryIndicatorSubLevel": AnyEncodable(rng.int(0...100)),
                "ansRate": AnyEncodable(rng.int(2...5)),
                "meanNightlyRecoveryRRI": AnyEncodable(rng.int(1020...1180)),
                "meanNightlyRecoveryRMSSD": AnyEncodable(rmssd),
                "meanNightlyRecoveryRespirationInterval": AnyEncodable(rng.int(3700...4100)),
                "meanBaselineRRI": AnyEncodable(1100),
                "sdBaselineRRI": AnyEncodable(45),
                "meanBaselineRMSSD": AnyEncodable(47),
                "sdBaselineRMSSD": AnyEncodable(6),
                "meanBaselineRespirationInterval": AnyEncodable(3900),
                "sdBaselineRespirationInterval": AnyEncodable(120),
            ]))

    // Every 5 minutes of real time, so the day the clocks go back has its repeated hour twice.
    var hr: [[String: AnyEncodable]] = []
    let localMidnight = dayStart.addingTimeInterval(TimeInterval(-berlin.secondsFromGMT(for: dayStart)))
    let nextMidnight = utc.date(byAdding: .day, value: 1, to: dayStart)!
    var instant = localMidnight
    while instant < nextMidnight.addingTimeInterval(TimeInterval(-berlin.secondsFromGMT(for: nextMidnight))) {
        let instantOffset = berlin.secondsFromGMT(for: instant)
        let minute = (Int(instant.timeIntervalSince(dayStart)) + instantOffset) / 60
        instant.addTimeInterval(300)
        let asleep = minute * 60 < sleepStart + duration
        let base = asleep ? 52 : (minute > 17 * 60 && minute < 18 * 60 ? 110 : 68)
        hr.append([
            "time": AnyEncodable(String(format: "%02d:%02d:00+%02d:00", minute / 60, minute % 60, instantOffset / 3600)),
            "hr": AnyEncodable(base + rng.int(-4...6)),
            "triggerType": AnyEncodable(base == 110 ? "HIGH_ACTIVITY" : "TIMED"),
        ])
    }
    heartRate.append(
        Entry(
            day: day, utcOffsetSeconds: offset, sampleCount: hr.count,
            payload: [
                "date": AnyEncodable(day), "samples": AnyEncodable(hr),
            ]))

    var beats: [[String: AnyEncodable]] = []
    for _ in 0..<120 {
        beats.append([
            "ppi": AnyEncodable(rng.int(1040...1160)),
            "errorEstimate": AnyEncodable(rng.int(4...12)),
            "blockerBit": AnyEncodable(rng.int(0...40) == 0 ? 1 : 0),
            "skinContactStatus": AnyEncodable(1),
            "skinContactSupported": AnyEncodable(1),
        ])
    }
    var sessions: [[String: AnyEncodable]] = [
        [
            "startTime": AnyEncodable(wallTime(dayStart, plusSeconds: 3 * 3600)),
            "trigger": AnyEncodable("AUTOMATIC"),
            "samples": AnyEncodable(beats),
        ]
    ]
    // Daytime sessions at a quarter past each hour, 34 beats each. Mostly calm; some days have a moderate or
    // stressed stretch. 17:15 falls in the afternoon run (high-activity heart rate), which stress leaves out.
    var beatCount = beats.count
    for hour in 7...20 {
        let spread: Int
        switch stressLevel(dayIndex: index, hour: hour) {
        case .calm: spread = daytimeRng.int(55...75)
        case .moderate: spread = daytimeRng.int(32...42)
        case .stressed: spread = daytimeRng.int(9...14)
        }
        var daytimeBeats: [[String: AnyEncodable]] = []
        for _ in 0..<34 {
            daytimeBeats.append([
                "ppi": AnyEncodable(980 + daytimeRng.int(-spread...spread)),
                "errorEstimate": AnyEncodable(daytimeRng.int(4...12)),
                "blockerBit": AnyEncodable(daytimeRng.int(0...80) == 0 ? 1 : 0),
                "skinContactStatus": AnyEncodable(1),
                "skinContactSupported": AnyEncodable(1),
            ])
        }
        beatCount += daytimeBeats.count
        sessions.append([
            "startTime": AnyEncodable(wallTime(dayStart, plusSeconds: hour * 3600 + 15 * 60)),
            "trigger": AnyEncodable("AUTOMATIC"),
            "samples": AnyEncodable(daytimeBeats),
        ])
    }
    // The last three days also have a session every 5 minutes from 07:00 to 20:55, besides the one at a quarter past.
    if index >= 27 {
        for hour in 7...20 {
            for minute in stride(from: 0, to: 60, by: 5) where minute != 15 {
                let spread: Int
                switch stressLevel(dayIndex: index, hour: hour) {
                case .calm: spread = denseRng.int(55...75)
                case .moderate: spread = denseRng.int(32...42)
                case .stressed: spread = denseRng.int(9...14)
                }
                var denseBeats: [[String: AnyEncodable]] = []
                for _ in 0..<34 {
                    denseBeats.append([
                        "ppi": AnyEncodable(980 + denseRng.int(-spread...spread)),
                        "errorEstimate": AnyEncodable(denseRng.int(4...12)),
                        "blockerBit": AnyEncodable(denseRng.int(0...80) == 0 ? 1 : 0),
                        "skinContactStatus": AnyEncodable(1),
                        "skinContactSupported": AnyEncodable(1),
                    ])
                }
                beatCount += denseBeats.count
                sessions.append([
                    "startTime": AnyEncodable(wallTime(dayStart, plusSeconds: hour * 3600 + minute * 60)),
                    "trigger": AnyEncodable("AUTOMATIC"),
                    "samples": AnyEncodable(denseBeats),
                ])
            }
        }
    }
    ppi.append(
        Entry(
            day: day, utcOffsetSeconds: offset, sampleCount: beatCount,
            payload: [
                "date": AnyEncodable(day),
                "sessions": AnyEncodable(sessions),
            ]))

    // Every 5 minutes of real time. The old hourly readings 00:00 to 06:00 keep their values from `rng`; the rest come from `skinRng`.
    var hourlyTemps: [Int: Double] = [:]
    for hour in 0...6 { hourlyTemps[hour * 60] = round1(rng.double(33.6...34.8)) }
    var temps: [[String: AnyEncodable]] = []
    var skinInstant = localMidnight
    let skinEnd = nextMidnight.addingTimeInterval(TimeInterval(-berlin.secondsFromGMT(for: nextMidnight)))
    while skinInstant < skinEnd {
        let instantOffset = berlin.secondsFromGMT(for: skinInstant)
        let minute = (Int(skinInstant.timeIntervalSince(dayStart)) + instantOffset) / 60
        skinInstant.addTimeInterval(300)
        let asleep = minute * 60 < sleepStart + duration
        let drift = 0.3 * sin(Double(index) * 0.7 + Double(minute) / 1440 * 2 * Double.pi)
        let fresh = round1(asleep ? skinRng.double(33.6...34.8) + drift : skinRng.double(31.6...33.4) + drift)
        let temperature = hourlyTemps.removeValue(forKey: minute) ?? fresh
        temps.append([
            "time": AnyEncodable(String(format: "%02d:%02d:00+%02d:00", minute / 60, minute % 60, instantOffset / 3600)),
            "temperature": AnyEncodable(temperature),
        ])
    }
    skinTemperature.append(
        Entry(
            day: day, utcOffsetSeconds: offset, sampleCount: temps.count,
            payload: [
                "date": AnyEncodable(day), "samples": AnyEncodable(temps),
            ]))

    var steps: [[String: AnyEncodable]] = []
    var totalSteps = 0
    for hour in 0..<24 {
        let count = hour < 7 || hour > 22 ? 0 : rng.int(150...900) + (hour == 17 ? 3000 : 0)
        totalSteps += count
        steps.append(["time": AnyEncodable(wallTime(dayStart, plusSeconds: hour * 3600)), "steps": AnyEncodable(count)])
    }
    activitySamples.append(
        Entry(
            day: day, utcOffsetSeconds: offset, sampleCount: steps.count,
            payload: [
                "date": AnyEncodable(day), "samples": AnyEncodable(steps),
            ]))

    let activityCalories = totalSteps / 25
    // About three exercise days a week (index 1, 3, 5 of each 7), a third of them with vigorous stretches.
    let exercises = index % 7 == 1 || index % 7 == 3 || index % 7 == 5
    let moderate = exercises ? classRng.int(1500...3000) : classRng.int(0...600)
    let vigorous = exercises && classRng.int(0...2) == 0 ? classRng.int(600...1200) : classRng.int(0...200)
    let classSeconds: [String: Int] = [
        "nonWear": classRng.int(0...1800), "sleep": 27000, "sedentary": 30000, "light": totalSteps * 4,
        "continuousModerate": moderate * 2 / 3, "intermittentModerate": moderate - moderate * 2 / 3,
        "continuousVigorous": vigorous / 2, "intermittentVigorous": vigorous - vigorous / 2,
    ]
    dailySummary.append(
        Entry(
            day: day, utcOffsetSeconds: offset, sampleCount: 1,
            payload: [
                "date": AnyEncodable(day),
                "steps": AnyEncodable(totalSteps),
                "activeDurationSeconds": AnyEncodable(totalSteps / 2),
                "calories": AnyEncodable(["bmr": 1720, "activity": activityCalories, "total": 1720 + activityCalories]),
                "activityClassSeconds": AnyEncodable(classSeconds),
            ]))
}

// Workouts have their own generator too. A 42-minute morning run on the last day, an unlabelled 75-minute evening ride the day before.
var workoutRng = SplitMix64(state: 20261103)

struct WorkoutFixture: Encodable {
    var session: String
    var start: String
    var utcOffsetSeconds: Int
    var bandSportId: Int?
    var durationSeconds: Int
    var calories: Int
    var cardioLoad: Double
    var cardioLoadRating: Int
    var trainingLoad: Double
    var averageHeartRate: Int
    var maxHeartRate: Int
    var heartRates: HeartRates
    var fileSize: Int
    var files: [File]

    struct HeartRates: Encodable {
        var intervalMs: Int
        var bpm: [Int]
    }

    struct File: Encodable {
        var name: String
        var data: Data
    }
}

func workout(day: Int, hour: Int, minute: Int, minutes: Int, sport: Int?, steady: ClosedRange<Int>, calories: Int, load: Double, rating: Int) -> WorkoutFixture {
    let dayStart = firstDay.addingTimeInterval(TimeInterval(day * 86400))
    let startSeconds = hour * 3600 + minute * 60
    let start = wallTime(dayStart, plusSeconds: startSeconds)
    let offset = berlin.secondsFromGMT(for: dayStart.addingTimeInterval(TimeInterval(startSeconds - 3600)))
    let bpm = (0..<(minutes * 60)).map { second in
        let warmUp = min(1.0, Double(second) / 300)
        return 95 + Int(warmUp * Double(workoutRng.int(steady) - 95))
    }
    let files = ["TSESS", "00/BASE", "00/SAMPLES"].map { name in
        WorkoutFixture.File(name: name, data: Data((0..<workoutRng.int(16...48)).map { _ in UInt8(workoutRng.int(0...255)) }))
    }
    let compact = { (value: String) in value.filter(\.isNumber) }
    let session = "\(compact(String(start.prefix(10))))/\(compact(String(start.dropFirst(11).prefix(8))))"
    return WorkoutFixture(
        session: session, start: start, utcOffsetSeconds: offset, bandSportId: sport, durationSeconds: minutes * 60, calories: calories,
        cardioLoad: load, cardioLoadRating: rating, trainingLoad: (load * 0.8).rounded(), averageHeartRate: bpm.reduce(0, +) / bpm.count,
        maxHeartRate: bpm.max()!, heartRates: .init(intervalMs: 1000, bpm: bpm), fileSize: files.reduce(0) { $0 + $1.data.count }, files: files
    )
}

let workouts = [
    workout(day: 28, hour: 18, minute: 30, minutes: 75, sport: nil, steady: 128...152, calories: 820, load: 182, rating: 4),
    workout(day: 29, hour: 7, minute: 10, minutes: 42, sport: 1, steady: 140...162, calories: 410, load: 87, rating: 3),
]

let outputDirectory = URL(
    fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "ios/Packages/VeselWearable/Sources/VeselWearableTesting/Resources/Fixtures"
)
.appending(path: "normal")
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
for (kind, entries) in [
    ("sleep", sleep), ("nightlyRecharge", recharge), ("heartRate", heartRate), ("ppi", ppi),
    ("skinTemperature", skinTemperature), ("activitySamples", activitySamples), ("dailySummary", dailySummary),
] {
    try encoder.encode(entries).write(to: outputDirectory.appending(path: "\(kind).json"))
}
try encoder.encode(workouts).write(to: outputDirectory.appending(path: "workouts.json"))
