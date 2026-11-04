import Foundation

public enum StressLevel: String, Sendable, Equatable {
    case calm, moderate, high

    /// Calm below 34, moderate 34–66, high 67 and up, on the level rounded as the screens show it.
    public init(level: Double) {
        let shown = level.rounded()
        if shown >= StressThresholds.highFrom {
            self = .high
        } else if shown >= StressThresholds.moderateFrom {
            self = .moderate
        } else {
            self = .calm
        }
    }

    public var word: String { rawValue }
}

/// One reading: 3 minutes of clock time. RMSSD is the root of the mean squared difference between neighbouring clean beats.
public struct StressWindow: Sendable, Equatable {
    public var start: Date
    public var seconds: Double
    /// Pairs of neighbouring clean beats.
    public var pairs: Int
    /// Milliseconds.
    public var rmssd: Double
    /// Local hour of the day, 0 to 23, in the zone the band recorded it in.
    public var hour: Int

    /// ln(RMSSD): high when calm, low under stress. RMSSD is held at 1 ms or more so the logarithm exists.
    public var value: Double { log(max(rmssd, 1)) }

    public init(start: Date, seconds: Double, pairs: Int, rmssd: Double, hour: Int) {
        self.start = start
        self.seconds = seconds
        self.pairs = pairs
        self.rmssd = rmssd
        self.hour = hour
    }
}

/// What happened to one daytime hour's beats, so an hour without a reading can say why.
public struct StressHourCounts: Sendable, Equatable {
    public var beats = 0
    /// Blocker on, with skin contact: the band marked the beat as movement.
    public var movement = 0
    public var offSkin = 0
    public var duringActivity = 0
    public var duringWorkout = 0

    public init() {}
}

/// What happened to a day's beats and 3-minute slices on the way to its readings.
public struct StressCounts: Sendable, Equatable {
    public var sessions = 0
    public var cleaning = PPICleaningCounts()
    public var outsideDaytime = 0
    public var tooFewPairs = 0
    public var duringActivity = 0
    public var duringWorkout = 0
    public var windows = 0
    /// Daytime hours with beats, by local hour.
    public var hours: [Int: StressHourCounts] = [:]

    public init() {}
}

/// Daytime stress from the band's beat-to-beat (PPI) sessions (`stress`, version 4: 3-minute readings gathered across
/// sessions, the hour's middle reading, and why an hour is empty). The rules are in `docs/how-it-works/stress.md`.
public enum Stress {
    public static let method = "stress"
    public static let version = 4

    /// The daytime readings of `sessions`, with the count of what was left out and why.
    /// `activityHeartRate` is resting + 40 % of the reserve; nil when either is unknown, and then only the band's own
    /// high-activity marks count. A reading that overlaps one of `workouts` (the owner's hidden ones left out) is skipped.
    public static func windows(sessions: [PPISession], heartRates: [HeartRateSample], activityHeartRate: Double?, workouts: [DateInterval]) -> (
        windows: [StressWindow], counts: StressCounts
    ) {
        var counts = StressCounts()
        counts.sessions = sessions.count
        let exercise = heartRates.filter { sample in
            sample.trigger == .highActivity || (activityHeartRate.map { Double(sample.bpm) > $0 } ?? false)
        }

        // Slices are 3 minutes of local clock time, keyed by their number since 1970 in local time.
        var slices: [Int: (offset: Int, differences: [Int])] = [:]
        func key(_ time: Date, _ offset: Int) -> Int { Int(((time.timeIntervalSince1970 + Double(offset)) / StressThresholds.windowSeconds).rounded(.down)) }
        for session in sessions {
            let offset = session.utcOffsetSeconds
            let (_, cleaning, pairs) = PPICleaning.clean(session.samples)
            counts.cleaning.add(cleaning)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: offset) ?? .gmt
            for sample in session.samples {
                if slices[key(sample.time, offset)] == nil { slices[key(sample.time, offset)] = (offset, []) }
                let hour = calendar.component(.hour, from: sample.time)
                guard StressThresholds.daytimeHours.contains(hour) else { continue }
                counts.hours[hour, default: StressHourCounts()].beats += 1
                if !sample.skinContact {
                    counts.hours[hour]?.offSkin += 1
                } else if sample.blocker {
                    counts.hours[hour]?.movement += 1
                }
            }
            for pair in pairs { slices[key(pair.time, offset)]?.differences.append(pair.difference) }
        }

        var windows: [StressWindow] = []
        for (index, slice) in slices.sorted(by: { $0.key < $1.key }) {
            let start = Date(timeIntervalSince1970: Double(index) * StressThresholds.windowSeconds - Double(slice.offset))
            let end = start.addingTimeInterval(StressThresholds.windowSeconds)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: slice.offset) ?? .gmt
            let hour = calendar.component(.hour, from: start)
            guard StressThresholds.daytimeHours.contains(hour) else {
                counts.outsideDaytime += 1
                continue
            }
            guard slice.differences.count >= StressThresholds.minimumPairs else {
                counts.tooFewPairs += 1
                continue
            }
            guard !workouts.contains(where: { $0.start < end && $0.end > start }) else {
                counts.duringWorkout += 1
                counts.hours[hour]?.duringWorkout += 1
                continue
            }
            let from = start.addingTimeInterval(-StressThresholds.activityMarginSeconds)
            let to = end.addingTimeInterval(StressThresholds.activityMarginSeconds)
            guard !exercise.contains(where: { $0.time >= from && $0.time <= to }) else {
                counts.duringActivity += 1
                counts.hours[hour]?.duringActivity += 1
                continue
            }
            windows.append(
                StressWindow(
                    start: start, seconds: StressThresholds.windowSeconds, pairs: slice.differences.count, rmssd: rmssd(slice.differences), hour: hour))
        }
        counts.windows = windows.count
        return (windows, counts)
    }

    static func rmssd(_ differences: [Int]) -> Double {
        let squares = differences.map { Double($0 * $0) }
        return (squares.reduce(0, +) / Double(squares.count)).squareRoot()
    }

    /// Each high reading counts for the gap to the next reading, at most 15 minutes; the last one counts for its own length.
    public static func highMinutes(of windows: [StressWindow], baseline: StressBaseline) -> (minutes: Double, readings: Int) {
        let sorted = windows.sorted { $0.start < $1.start }
        var seconds = 0.0
        var readings = 0
        for (index, window) in sorted.enumerated() where StressLevel(level: baseline.level(of: window.value)) == .high {
            readings += 1
            let gap = index + 1 < sorted.count ? sorted[index + 1].start.timeIntervalSince(window.start) : window.seconds
            seconds += min(gap, StressThresholds.longestCountedGap)
        }
        return (seconds / 60, readings)
    }

    /// The 2 hours with the most high-stress minutes, counted as `highMinutes` does but cut at the span's end.
    /// Nil without a high reading.
    public static func busiestSpan(of windows: [StressWindow], baseline: StressBaseline) -> (minutes: Double, start: Date)? {
        let sorted = windows.sorted { $0.start < $1.start }
        var high: [(start: Date, seconds: Double)] = []
        for (index, window) in sorted.enumerated() where StressLevel(level: baseline.level(of: window.value)) == .high {
            let gap = index + 1 < sorted.count ? sorted[index + 1].start.timeIntervalSince(window.start) : window.seconds
            high.append((window.start, min(gap, StressThresholds.longestCountedGap)))
        }
        var best: (seconds: Double, start: Date)?
        for first in high {
            let end = first.start.addingTimeInterval(StressThresholds.busiestSpan)
            let seconds =
                high
                .filter { $0.start >= first.start && $0.start < end }
                .map { min($0.seconds, end.timeIntervalSince($0.start)) }
                .reduce(0, +)
            if seconds > (best?.seconds ?? -1) { best = (seconds, first.start) }
        }
        return best.map { ($0.seconds / 60, $0.start) }
    }

    /// The numbers stored for one day: always its readings count, and once the baseline is ready also its hourly
    /// levels, high-stress minutes, the busiest 2 hours and the latest reading.
    public static func metrics(day: DayKey, windows: [StressWindow], counts: StressCounts, baseline: StressBaseline.Outcome, computedAt: Date)
        -> [ComputedMetric]
    {
        func metric(_ kind: String, hour: Int? = nil, _ value: Double, _ unit: String, inputs: [Explanation.Input], _ text: String) -> ComputedMetric {
            ComputedMetric(
                kind: kind, day: day, hour: hour, value: value, unit: unit,
                explanation: Explanation(method: method, version: version, inputs: inputs, text: text),
                computedAt: computedAt
            )
        }
        var inputs: [Explanation.Input] = [
            .init(name: "sessions", value: Double(counts.sessions), unit: "sessions"),
            .init(name: "beats", value: Double(counts.cleaning.intervals), unit: "beats"),
            .init(name: "flagged", value: Double(counts.cleaning.flagged), unit: "beats"),
            .init(name: "outOfRange", value: Double(counts.cleaning.outOfRange), unit: "beats"),
            .init(name: "jumps", value: Double(counts.cleaning.jumps), unit: "beats"),
            .init(name: "outsideDaytime", value: Double(counts.outsideDaytime), unit: "readings"),
            .init(name: "tooFewPairs", value: Double(counts.tooFewPairs), unit: "readings"),
            .init(name: "duringExercise", value: Double(counts.duringActivity), unit: "readings"),
            .init(name: "duringWorkout", value: Double(counts.duringWorkout), unit: "readings"),
        ]
        var ready: StressBaseline?
        let learning: String
        switch baseline {
        case .learning(let days):
            inputs.append(.init(name: "baselineDays", value: Double(days), unit: "days"))
            learning =
                "Your calm baseline needs \(StressThresholds.minimumDays) earlier days with at least \(StressThresholds.minimumWindowsPerDay) readings each; Vesel has \(days)."
        case .ready(let found):
            ready = found
            inputs += [
                .init(name: "baselineDays", value: Double(found.days), unit: "days"),
                .init(name: "baselineReadings", value: Double(found.windows), unit: "readings"),
                .init(name: "baseline", value: found.baseline, unit: "ln RMSSD"),
                .init(name: "floor", value: found.floor, unit: "ln RMSSD"),
            ]
            learning =
                "Your calm baseline is the 80th percentile of \(found.windows) readings from \(found.days) days: an RMSSD of \(NumberText.decimal(exp(found.baseline), 0)) ms. Your floor is the 5th percentile: \(NumberText.decimal(exp(found.floor), 0)) ms."
        }
        let cleaning = counts.cleaning
        var result = [
            metric(
                MetricKind.stressReadings, Double(windows.count), "readings", inputs: inputs,
                "\(windows.count) clean readings between \(pad(StressThresholds.daytimeHours.lowerBound)):00 and \(pad(StressThresholds.daytimeHours.upperBound)):00. Of \(cleaning.intervals) beats, \(cleaning.flagged) were flagged by the band (movement or no skin contact), \(cleaning.outOfRange) were outside \(StressThresholds.minimumIntervalMs)–\(StressThresholds.maximumIntervalMs) ms and \(cleaning.jumps) jumped more than \(NumberText.decimal(StressThresholds.maximumJump * 100, 0)) % from the one before. A reading is \(NumberText.decimal(StressThresholds.windowSeconds / 60, 0)) minutes of clock time with at least \(StressThresholds.minimumPairs) pairs of neighbouring clean beats, from every session in it; \(counts.tooFewPairs) had fewer, \(counts.duringWorkout) were inside workouts and \(counts.duringActivity) were skipped as exercise. \(learning)"
            )
        ]
        guard let ready else { return result }

        func range(_ hour: Int) -> String { "\(pad(hour)):00–\(pad(hour + 1)):00" }
        let byHour = Dictionary(grouping: windows, by: \.hour)
        for (hour, inHour) in byHour.sorted(by: { $0.key < $1.key }) {
            let levels = inHour.map { ready.level(of: $0.value) }.sorted()
            let middle = StressBaseline.percentile(levels, 0.5)
            let top = levels.last ?? 0
            result.append(
                metric(
                    MetricKind.stressHourly, hour: hour, middle, "of 100",
                    inputs: [
                        .init(name: "readings", value: Double(inHour.count), unit: "readings"),
                        .init(name: "highest", value: top, unit: "of 100"),
                        .init(name: "baseline", value: ready.baseline, unit: "ln RMSSD"),
                        .init(name: "floor", value: ready.floor, unit: "ln RMSSD"),
                    ],
                    "The middle of \(inHour.count) readings from \(range(hour)) is level \(NumberText.decimal(middle, 0)) (\(StressLevel(level: middle).word)); the highest was \(NumberText.decimal(top, 0)). Each reading is \(NumberText.decimal(StressThresholds.windowSeconds / 60, 0)) minutes of still beats. Level = (baseline − ln RMSSD) ÷ (baseline − floor) × 100, held between 0 and 100, against your calm baseline of \(NumberText.decimal(exp(ready.baseline), 0)) ms and floor of \(NumberText.decimal(exp(ready.floor), 0)) ms. Calm is below \(NumberText.decimal(StressThresholds.moderateFrom, 0)), moderate \(NumberText.decimal(StressThresholds.moderateFrom, 0))–\(NumberText.decimal(StressThresholds.highFrom - 1, 0)), high \(NumberText.decimal(StressThresholds.highFrom, 0)) and up."
                ))
        }
        for (hour, hourCounts) in counts.hours.sorted(by: { $0.key < $1.key }) where byHour[hour] == nil {
            let reason = StressEmptyHour.Reason(hourCounts)
            result.append(
                metric(
                    MetricKind.stressEmptyHour, hour: hour, Double(hourCounts.beats), "beats",
                    inputs: [
                        .init(name: "movement", value: Double(hourCounts.movement), unit: "beats"),
                        .init(name: "offSkin", value: Double(hourCounts.offSkin), unit: "beats"),
                        .init(name: "duringExercise", value: Double(hourCounts.duringActivity), unit: "readings"),
                        .init(name: "duringWorkout", value: Double(hourCounts.duringWorkout), unit: "readings"),
                    ],
                    "No reading from \(range(hour)). Of \(hourCounts.beats) beats, the band marked \(hourCounts.movement) as movement and \(hourCounts.offSkin) had no skin contact; \(hourCounts.duringActivity) readings were skipped as exercise and \(hourCounts.duringWorkout) were inside workouts. \(reason.sentence)"
                ))
        }
        let high = highMinutes(of: windows, baseline: ready)
        result.append(
            metric(
                MetricKind.stressHighMinutes, high.minutes, "min",
                inputs: [
                    .init(name: "highReadings", value: Double(high.readings), unit: "readings"),
                    .init(name: "baseline", value: ready.baseline, unit: "ln RMSSD"),
                    .init(name: "floor", value: ready.floor, unit: "ln RMSSD"),
                ],
                "\(high.readings) readings were high (level \(NumberText.decimal(StressThresholds.highFrom, 0)) or more against your calm baseline of \(NumberText.decimal(exp(ready.baseline), 0)) ms and floor of \(NumberText.decimal(exp(ready.floor), 0)) ms). Each counts for the gap to the next reading, at most \(NumberText.decimal(StressThresholds.longestCountedGap / 60, 0)) minutes, and the last one for its own length: \(DurationText.hoursMinutes(minutes: high.minutes))."
            ))
        if let busiest = busiestSpan(of: windows, baseline: ready) {
            result.append(
                metric(
                    MetricKind.stressBusiestSpan, busiest.minutes, "min",
                    inputs: [
                        .init(name: "spanStart", value: busiest.start.timeIntervalSince1970, unit: "unix s"),
                        .init(name: "spanSeconds", value: StressThresholds.busiestSpan, unit: "s"),
                        .init(name: "baseline", value: ready.baseline, unit: "ln RMSSD"),
                        .init(name: "floor", value: ready.floor, unit: "ln RMSSD"),
                    ],
                    "The \(NumberText.decimal(StressThresholds.busiestSpan / 3600, 0)) hours with the most high stress, from the first high reading in them, held \(DurationText.hoursMinutes(minutes: busiest.minutes)) of it, counted like the day's high-stress minutes but cut at the end of the span."
                ))
        }
        if let latest = windows.max(by: { $0.start < $1.start }) {
            let level = ready.level(of: latest.value)
            result.append(
                metric(
                    MetricKind.stressNow, level, "of 100",
                    inputs: [
                        .init(name: "windowStart", value: latest.start.timeIntervalSince1970, unit: "unix s"),
                        .init(name: "rmssd", value: latest.rmssd, unit: "ms"),
                        .init(name: "baseline", value: ready.baseline, unit: "ln RMSSD"),
                        .init(name: "floor", value: ready.floor, unit: "ln RMSSD"),
                    ],
                    "The day's latest reading has an RMSSD of \(NumberText.decimal(latest.rmssd, 0)) ms, level \(NumberText.decimal(level, 0)) (\(StressLevel(level: level).word)) against your calm baseline of \(NumberText.decimal(exp(ready.baseline), 0)) ms and floor of \(NumberText.decimal(exp(ready.floor), 0)) ms. It counts as \"now\" for \(NumberText.decimal(StressThresholds.nowFor / 60, 0)) minutes."
                ))
        }
        return result
    }

    private static func pad(_ hour: Int) -> String { hour < 10 ? "0\(hour)" : "\(hour)" }
}

/// The latest reading as a level, read back from `stress.now`.
public struct StressNow: Sendable, Equatable {
    public var level: Double
    public var windowStart: Date
    public var explanation: Explanation

    public init?(_ metric: ComputedMetric) {
        guard metric.kind == MetricKind.stressNow,
            let start = metric.explanation.inputs.first(where: { $0.name == "windowStart" })?.value
        else { return nil }
        level = metric.value
        windowStart = Date(timeIntervalSince1970: start)
        explanation = metric.explanation
    }

    public var band: StressLevel { StressLevel(level: level) }

    /// "Now" means a reading under 30 minutes old.
    public func isRecent(at now: Date) -> Bool {
        let age = now.timeIntervalSince(windowStart)
        return age >= 0 && age < StressThresholds.nowFor
    }

    /// "Calm now.", "Moderately stressed now.", "Highly stressed now."
    public var sentence: String {
        switch band {
        case .calm: "Calm now."
        case .moderate: "Moderately stressed now."
        case .high: "Highly stressed now."
        }
    }

    public static let noRecentReading = "No recent reading."
}

/// What a past day says in place of "Calm now.".
public enum StressDay {
    /// "45 m of high stress.", "1 h of high stress.", "No high stress.", nil when the day has no stress numbers.
    public static func sentence(highMinutes: Double?) -> String? {
        guard let highMinutes else { return nil }
        let total = Int(highMinutes.rounded())
        if total == 0 { return "No high stress." }
        let duration = total % 60 == 0 ? "\(total / 60) h" : DurationText.hoursMinutes(minutes: highMinutes)
        return "\(duration) of high stress."
    }

    /// What the Calm row says for a past day: "45 m", "0 m", or "—" when the day has no stress numbers.
    public static func ringText(highMinutes: Double?) -> String {
        highMinutes.map { DurationText.hoursMinutes(minutes: $0) } ?? "—"
    }
}

/// The day's busiest 2 hours of high stress, read back from `stress.busiestSpan`.
public struct StressSpan: Sendable, Equatable {
    public var minutes: Double
    public var start: Date
    public var end: Date
    public var explanation: Explanation

    public init?(_ metric: ComputedMetric) {
        guard metric.kind == MetricKind.stressBusiestSpan,
            let start = metric.explanation.inputs.first(where: { $0.name == "spanStart" })?.value,
            let seconds = metric.explanation.inputs.first(where: { $0.name == "spanSeconds" })?.value
        else { return nil }
        minutes = metric.value
        self.start = Date(timeIntervalSince1970: start)
        end = self.start.addingTimeInterval(seconds)
        explanation = metric.explanation
    }
}

/// A daytime hour with beats but no reading, read back from `stress.emptyHour`.
public struct StressEmptyHour: Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        case workout, exercise, offSkin, movement, fewBeats

        /// A workout or exercise explains the hour first; then what most of its beats were; else too few clean beats.
        init(_ counts: StressHourCounts) {
            if counts.duringWorkout > 0 {
                self = .workout
            } else if counts.duringActivity > 0 {
                self = .exercise
            } else if counts.offSkin * 2 > counts.beats {
                self = .offSkin
            } else if counts.movement * 2 > counts.beats {
                self = .movement
            } else {
                self = .fewBeats
            }
        }

        init(inputs: [Explanation.Input], beats: Double) {
            func input(_ name: String) -> Int { Int(inputs.first { $0.name == name }?.value ?? 0) }
            var counts = StressHourCounts()
            counts.beats = Int(beats)
            counts.movement = input("movement")
            counts.offSkin = input("offSkin")
            counts.duringActivity = input("duringExercise")
            counts.duringWorkout = input("duringWorkout")
            self.init(counts)
        }

        /// What the hour's scrub reads after "no reading".
        public var phrase: String {
            switch self {
            case .workout: "inside a workout"
            case .exercise: "skipped as exercise"
            case .offSkin: "band off the skin"
            case .movement: "mostly movement"
            case .fewBeats: "too few clean beats"
            }
        }

        var sentence: String {
            switch self {
            case .workout: "The still moments were inside a workout."
            case .exercise: "The still moments were skipped as exercise."
            case .offSkin: "The band was off the skin for most of it."
            case .movement: "No still moments: the Loop marked most beats as movement."
            case .fewBeats: "Too few clean beats for a reading."
            }
        }
    }

    public var hour: Int
    public var reason: Reason

    public init?(_ metric: ComputedMetric) {
        guard metric.kind == MetricKind.stressEmptyHour, let hour = metric.hour else { return nil }
        self.hour = hour
        reason = Reason(inputs: metric.explanation.inputs, beats: metric.value)
    }
}
