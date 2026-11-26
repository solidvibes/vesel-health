import Foundation

/// Turns stored readings into what Vesel writes to Health. Pure: VeselStorage gathers the rows, the writer saves the items.
public enum HealthMapping {
    /// Changing how a kind is mapped bumps its version: every unit of that kind is written again.
    public static func version(_ kind: HealthKind) -> Int {
        switch kind {
        case .heartRate, .restingHeartRate, .respiratoryRate, .sleep, .steps: 1
        }
    }

    /// Each 24/7 reading at its time.
    public static func heartRate(_ samples: [HeartRateSample]) -> [HealthItem] {
        samples.map { sample in
            HealthItem(
                kind: .heartRate, start: sample.time, end: sample.time, value: .quantity(Double(sample.bpm), .bpm),
                syncId: "vesel.hr.\(Int64(sample.time.timeIntervalSince1970))"
            )
        }
    }

    /// The night's resting heart rate over its sleep window; without one, the night's day, midnight to midnight, in `utcOffsetSeconds`.
    public static func restingHeartRate(night: DayKey, bpm: Double, sleep: SleepNight?, utcOffsetSeconds: Int) -> HealthItem {
        let window = nightWindow(night: night, sleep: sleep, utcOffsetSeconds: utcOffsetSeconds)
        return HealthItem(
            kind: .restingHeartRate, start: window.start, end: window.end, value: .quantity(bpm, .bpm), syncId: "vesel.restingHR.\(night)")
    }

    /// The night's breathing rate, over the same window as resting heart rate.
    public static func respiratoryRate(night: DayKey, breathsPerMinute: Double, sleep: SleepNight?, utcOffsetSeconds: Int) -> HealthItem {
        let window = nightWindow(night: night, sleep: sleep, utcOffsetSeconds: utcOffsetSeconds)
        return HealthItem(
            kind: .respiratoryRate, start: window.start, end: window.end, value: .quantity(breathsPerMinute, .breathsPerMinute),
            syncId: "vesel.breathing.\(night)")
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
            HealthItem(kind: .sleep, start: night.start, end: night.end, value: .sleep(.inBed), syncId: "\(prefix).inBed")
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
                    kind: .sleep, start: start, end: min(end, night.end), value: .sleep(value),
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
                kind: .steps,
                start: Date(timeIntervalSince1970: TimeInterval(start)),
                end: Date(timeIntervalSince1970: TimeInterval(min(start + 3600, hour.last + 60))),
                value: .quantity(Double(hour.steps), .count),
                syncId: "vesel.steps.\(start)"
            )
        }
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
