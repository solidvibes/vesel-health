import Foundation

/// One night's sleep as numbers: how long, how efficient, how it split into stages, and the lowest heart rate.
/// The stages are Polar's; Vesel only adds them up.
public struct SleepSummary: Sendable, Equatable {
    public static let method = "sleep.summary"
    public static let version = 1

    public var night: DayKey
    public var start: Date
    public var end: Date
    public var inBedSeconds: Int
    public var asleepSeconds: Int
    public var stageSeconds: [SleepState: Int]
    public var lowestHeartRate: Int?

    /// Time asleep ÷ time in bed, 0...1. Zero when the night has no length.
    public var efficiency: Double {
        inBedSeconds > 0 ? Double(asleepSeconds) / Double(inBedSeconds) : 0
    }

    /// `heartRates` may hold any samples; only those between sleep start and end count.
    public init(_ sleep: SleepNight, heartRates: [HeartRateSample]) {
        night = sleep.night
        start = sleep.start
        end = sleep.end
        inBedSeconds = max(0, Int(sleep.end.timeIntervalSince(sleep.start).rounded()))

        let phases = sleep.phases.sorted { $0.secondsFromStart < $1.secondsFromStart }
        var stages: [SleepState: Int] = [:]
        if let first = phases.first, first.secondsFromStart > 0 {
            stages[.wake, default: 0] += min(first.secondsFromStart, inBedSeconds)
        }
        for (index, phase) in phases.enumerated() {
            let from = min(max(phase.secondsFromStart, 0), inBedSeconds)
            let to = index + 1 < phases.count ? min(max(phases[index + 1].secondsFromStart, 0), inBedSeconds) : inBedSeconds
            stages[phase.state, default: 0] += max(0, to - from)
        }
        if phases.isEmpty { stages[.unknown] = inBedSeconds }
        stageSeconds = stages
        asleepSeconds = inBedSeconds - (stages[.wake] ?? 0)

        lowestHeartRate =
            heartRates
            .filter { $0.time >= sleep.start && $0.time <= sleep.end }
            .map(\.bpm)
            .min()
    }

    public func metrics(computedAt: Date) -> [ComputedMetric] {
        func metric(_ kind: String, _ value: Double, _ unit: String, inputs: [Explanation.Input], _ text: String) -> ComputedMetric {
            ComputedMetric(
                kind: kind, day: night, hour: nil, value: value, unit: unit,
                explanation: Explanation(method: Self.method, version: Self.version, inputs: inputs, text: text),
                computedAt: computedAt
            )
        }
        let inBedMinutes = Double(inBedSeconds) / 60
        let asleepMinutes = Double(asleepSeconds) / 60
        let wakeMinutes = Double(stageSeconds[.wake] ?? 0) / 60
        var result = [
            metric(
                MetricKind.sleepInBed, inBedMinutes, "min",
                inputs: [.init(name: "sleepStartToEnd", value: inBedMinutes, unit: "min")],
                "Time in bed is the time from the start to the end of the sleep Polar recorded."
            ),
            metric(
                MetricKind.sleepAsleep, asleepMinutes, "min",
                inputs: [.init(name: "inBed", value: inBedMinutes, unit: "min"), .init(name: "awake", value: wakeMinutes, unit: "min")],
                "Time asleep is the time in bed minus the time Polar marks as awake."
            ),
            metric(
                MetricKind.sleepEfficiency, efficiency * 100, "%",
                inputs: [.init(name: "asleep", value: asleepMinutes, unit: "min"), .init(name: "inBed", value: inBedMinutes, unit: "min")],
                "Efficiency is the time asleep divided by the time in bed."
            ),
        ]
        for state in [SleepState.light, .deep, .rem, .wake] {
            let minutes = Double(stageSeconds[state] ?? 0) / 60
            result.append(
                metric(
                    MetricKind.sleepStage(state), minutes, "min",
                    inputs: [.init(name: "stage", value: minutes, unit: "min")],
                    "Minutes Polar's sleep phases spend \(state == .wake ? "awake" : "in \(state.rawValue) sleep") between sleep start and end."
                ))
        }
        if let lowestHeartRate {
            result.append(
                metric(
                    MetricKind.sleepLowestHeartRate, Double(lowestHeartRate), "bpm",
                    inputs: [.init(name: "lowest", value: Double(lowestHeartRate), unit: "bpm")],
                    "The lowest of the band's 24/7 heart-rate readings between sleep start and end."
                ))
        }
        return result
    }
}
