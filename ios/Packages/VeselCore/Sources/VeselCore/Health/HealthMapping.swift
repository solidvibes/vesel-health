import Foundation

/// Turns stored readings into what Vesel writes to Health. Pure: VeselStorage gathers the rows, the writer saves the items.
public enum HealthMapping {
    /// Changing how a kind is mapped bumps its version: every unit of that kind is written again.
    public static func version(_ kind: HealthKind) -> Int {
        switch kind {
        case .heartRate, .restingHeartRate, .respiratoryRate, .sleep, .steps, .hrv, .energy, .workout: 1
        }
    }

    /// Each 24/7 reading at its time. Readings inside `workouts` are left out: they go with the workout (only when Workouts
    /// are allowed in Health, so the caller passes none otherwise).
    public static func heartRate(_ samples: [HeartRateSample], leavingOut workouts: [DateInterval] = []) -> [HealthItem] {
        samples.filter { sample in !workouts.contains { $0.contains(sample.time) } }.map { sample in
            HealthItem(
                type: .heartRate, start: sample.time, end: sample.time, value: .quantity(Double(sample.bpm), .bpm),
                syncId: "vesel.hr.\(Int64(sample.time.timeIntervalSince1970))"
            )
        }
    }

    /// The night's resting heart rate over its sleep window; without one, the night's day, midnight to midnight, in `utcOffsetSeconds`.
    public static func restingHeartRate(night: DayKey, bpm: Double, sleep: SleepNight?, utcOffsetSeconds: Int) -> HealthItem {
        let window = nightWindow(night: night, sleep: sleep, utcOffsetSeconds: utcOffsetSeconds)
        return HealthItem(
            type: .restingHeartRate, start: window.start, end: window.end, value: .quantity(bpm, .bpm), syncId: "vesel.restingHR.\(night)")
    }

    /// The night's breathing rate, over the same window as resting heart rate.
    public static func respiratoryRate(night: DayKey, breathsPerMinute: Double, sleep: SleepNight?, utcOffsetSeconds: Int) -> HealthItem {
        let window = nightWindow(night: night, sleep: sleep, utcOffsetSeconds: utcOffsetSeconds)
        return HealthItem(
            type: .respiratoryRate, start: window.start, end: window.end, value: .quantity(breathsPerMinute, .breathsPerMinute),
            syncId: "vesel.breathing.\(night)")
    }

    /// The night's SDNN (`NightSDNN`), over the same window as resting heart rate.
    public static func hrv(night: DayKey, ms: Double, sleep: SleepNight?, utcOffsetSeconds: Int) -> HealthItem {
        let window = nightWindow(night: night, sleep: sleep, utcOffsetSeconds: utcOffsetSeconds)
        return HealthItem(type: .hrv, start: window.start, end: window.end, value: .quantity(ms, .ms), syncId: "vesel.hrv.\(night)")
    }

    private static func nightWindow(night: DayKey, sleep: SleepNight?, utcOffsetSeconds: Int) -> (start: Date, end: Date) {
        if let sleep { return (sleep.start, sleep.end) }
        let zone = TimeZone(secondsFromGMT: utcOffsetSeconds) ?? .gmt
        return (night.start(in: zone), night.adding(days: 1).start(in: zone))
    }

    /// In bed from start to end, then each run of one stage as a piece: light → core, deep → deep, rem → rem, wake → awake.
    /// Unknown stretches are left out. Before the first phase is awake, as `SleepNight.state(at:)` counts it.
    public static func sleep(_ night: SleepNight) -> [HealthItem] {
        let prefix = "vesel.sleep.\(night.night)"
        var items = [
            HealthItem(type: .sleep, start: night.start, end: night.end, value: .sleep(.inBed), syncId: "\(prefix).inBed")
        ]
        guard !night.phases.isEmpty else { return items }
        var changes: [(offset: Int, state: SleepState)] = [(0, .wake)]
        for phase in night.phases.sorted(by: { $0.secondsFromStart < $1.secondsFromStart }) {
            let offset = max(phase.secondsFromStart, 0)
            if changes.last?.offset == offset { changes.removeLast() }
            if changes.last?.state != phase.state { changes.append((offset, phase.state)) }
        }
        for (index, change) in changes.enumerated() {
            let start = night.start.addingTimeInterval(TimeInterval(change.offset))
            let end = index + 1 < changes.count ? night.start.addingTimeInterval(TimeInterval(changes[index + 1].offset)) : night.end
            guard let value = stage(change.state), start < min(end, night.end) else { continue }
            items.append(
                HealthItem(
                    type: .sleep, start: start, end: min(end, night.end), value: .sleep(value),
                    syncId: "\(prefix).\(Int64(start.timeIntervalSince1970))"))
        }
        return items
    }

    private static func stage(_ state: SleepState) -> HealthSleepValue? {
        switch state {
        case .light: .core
        case .deep: .deep
        case .rem: .rem
        case .wake: .awake
        case .unknown: nil
        }
    }

    /// The day's per-minute steps summed per real hour, each minute in its own UTC offset, so the hour that repeats when
    /// clocks go back is two hours. Hours with no steps are left out, and so are samples dated another day. An hour ends at
    /// the earlier of its end and a minute after its last sample, so today's current hour never ends in the future.
    public static func steps(day: DayKey, samples: [HourlySteps.Sample]) -> [HealthItem] {
        let prefix = day.description + "T"
        var hours: [Int64: (steps: Int, last: Int64)] = [:]
        for sample in samples where sample.time.hasPrefix(prefix) {
            guard let time = try? Date(sample.time, strategy: .iso8601), let offset = utcOffset(sample.time) else { continue }
            let seconds = Int64(time.timeIntervalSince1970)
            let local = seconds + Int64(offset)
            let hourStart = local - ((local % 3600) + 3600) % 3600 - Int64(offset)
            let current = hours[hourStart] ?? (0, seconds)
            hours[hourStart] = (current.steps + sample.steps, max(current.last, seconds))
        }
        return hours.sorted { $0.key < $1.key }.compactMap { start, hour in
            guard hour.steps > 0 else { return nil }
            return HealthItem(
                type: .steps,
                start: Date(timeIntervalSince1970: TimeInterval(start)),
                end: Date(timeIntervalSince1970: TimeInterval(min(start + 3600, hour.last + 60))),
                value: .quantity(Double(hour.steps), .count),
                syncId: "vesel.steps.\(start)"
            )
        }
    }

    /// Resting energy is Polar's BMR for the day; active energy is its activity calories, less what the day's workouts carry
    /// when Workouts are allowed (`workouts` is nil otherwise). Both run from midnight in the daily summary's offset to the
    /// next midnight, or to when the summary was read if that was earlier (today). Nothing is written for 0 kcal.
    public static func energy(
        day: DayKey, calories: ActivityDay.Calories, utcOffsetSeconds: Int, readAt: Date, workouts: [Workout]?
    ) -> [HealthItem] {
        let zone = TimeZone(secondsFromGMT: utcOffsetSeconds) ?? .gmt
        let start = day.start(in: zone)
        let midnight = day.adding(days: 1).start(in: zone)
        let end = readAt > start ? min(midnight, readAt) : midnight
        let inWorkouts = (workouts ?? []).compactMap { activeEnergy($0, bmr: calories.bmr) }.reduce(0, +)
        let active = max(0, Double(calories.activity) - inWorkouts)
        var items: [HealthItem] = []
        if active > 0 {
            items.append(HealthItem(type: .activeEnergy, start: start, end: end, value: .quantity(active, .kcal), syncId: "vesel.activeEnergy.\(day)"))
        }
        if calories.bmr > 0 {
            items.append(
                HealthItem(
                    type: .restingEnergy, start: start, end: end, value: .quantity(Double(calories.bmr), .kcal), syncId: "vesel.restingEnergy.\(day)"))
        }
        return items
    }

    /// Polar's workout calories less the resting share of its time (BMR × duration ÷ a day). Nil without calories.
    public static func activeEnergy(_ workout: Workout, bmr: Int) -> Double? {
        workout.calories.map { max(0, Double($0) - Double(bmr) * Double(workout.durationSeconds) / 86_400) }
    }

    /// A shown workout with its sport (only the Loop's or the owner's; a guess is Other), its active energy, its heart rate
    /// (the Loop's workout readings, else the 24/7 readings inside it) and its stored route. Nil for "Not a workout".
    public static func workout(
        _ workout: Workout, label: WorkoutLabel, route: [RoutePoint], bmr: Int, dayHeartRates: [HeartRateSample]
    ) -> HealthItem? {
        guard !label.hidden else { return nil }
        let prefix = "vesel.workout.\(workout.session)"
        let interval = workout.interval
        var samples: [HealthItem] = []
        if let energy = activeEnergy(workout, bmr: bmr), energy > 0 {
            samples.append(
                HealthItem(type: .activeEnergy, start: interval.start, end: interval.end, value: .quantity(energy, .kcal), syncId: "\(prefix).energy"))
        }
        var readings: [HeartRateSample] = []
        if let own = workout.heartRates, own.intervalMs > 0 {
            // Readings past the workout's end are left out: a workout's samples lie inside it.
            readings = own.bpm.enumerated().compactMap { index, bpm in
                let time = interval.start.addingTimeInterval(Double(index * own.intervalMs) / 1000)
                return bpm > 0 && interval.contains(time) ? HeartRateSample(time: time, bpm: bpm, trigger: .timed) : nil
            }
        }
        if readings.isEmpty { readings = dayHeartRates.filter { interval.contains($0.time) } }
        samples += readings.map { reading in
            HealthItem(
                type: .heartRate, start: reading.time, end: reading.time, value: .quantity(Double(reading.bpm), .bpm),
                syncId: "\(prefix).hr.\(Int64((reading.time.timeIntervalSince1970 * 1000).rounded()))")
        }
        let activity: HealthWorkoutActivity =
            switch (label.source, label.sport) {
            case (.owner, .running?), (.band, .running?): .running
            case (.owner, .cycling?), (.band, .cycling?): .cycling
            case (.owner, .swimming?), (.band, .swimming?): .swimming
            case (.owner, .strength?), (.band, .strength?): .strength
            default: .other
            }
        return HealthItem(
            type: .workout, start: interval.start, end: interval.end,
            value: .workout(HealthWorkout(activity: activity, samples: samples, route: route)), syncId: prefix)
    }

    /// "+01:00" at the end of a band time, in seconds.
    private static func utcOffset(_ time: String) -> Int? {
        let suffix = time.suffix(6)
        guard suffix.count == 6, let sign = suffix.first, sign == "+" || sign == "-",
            let hours = Int(suffix.dropFirst().prefix(2)), suffix.dropFirst(3).first == ":", let minutes = Int(suffix.suffix(2))
        else { return nil }
        return (sign == "-" ? -1 : 1) * (hours * 3600 + minutes * 60)
    }
}
