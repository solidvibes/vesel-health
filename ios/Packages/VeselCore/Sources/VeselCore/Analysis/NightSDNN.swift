import Foundation

/// The night's heart rate variability as SDNN, for Apple Health only (no screen shows it). Apple's own SDNN readings are short
/// recordings at rest, so this uses the band's beat-to-beat recordings made during sleep, one SDNN each, and takes the middle
/// one so a restless recording doesn't move the night. Polar's RMSSD is a different measure and is never written as SDNN.
public enum NightSDNN {
    public static let kind = "heart.sdnn"
    public static let method = "sdnn"
    public static let version = 1

    static let minimumBeats = 60
    static let minimumKept = 0.8
    static let minimumRecordings = 5

    /// Each recording lying entirely inside `sleep` is cleaned as stress cleans it; it counts with at least 60 clean beats
    /// and 80 % of its intervals kept, and its SDNN is the sample standard deviation of its clean intervals. Nil with fewer
    /// than 5 counted recordings.
    public static func metric(sleep: SleepNight, sessions: [PPISession], computedAt: Date) -> ComputedMetric? {
        let inside = sessions.filter { session in
            session.start >= sleep.start && session.start <= sleep.end && session.samples.allSatisfy { $0.time <= sleep.end }
        }
        var values: [Double] = []
        var beats = 0
        for session in inside {
            let cleaned = PPICleaning.clean(session.samples)
            guard cleaned.counts.intervals > 0, cleaned.kept.count >= minimumBeats,
                Double(cleaned.kept.count) / Double(cleaned.counts.intervals) >= minimumKept
            else { continue }
            values.append(standardDeviation(cleaned.kept.map { Double($0.intervalMs) }))
            beats += cleaned.kept.count
        }
        guard values.count >= minimumRecordings else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        let median = sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
        return ComputedMetric(
            kind: kind, day: sleep.night, hour: nil, value: median, unit: "ms",
            explanation: Explanation(
                method: method, version: version,
                inputs: [
                    .init(name: "recordingsCounted", value: Double(values.count), unit: "count"),
                    .init(name: "recordingsInSleep", value: Double(inside.count), unit: "count"),
                    .init(name: "cleanBeats", value: Double(beats), unit: "count"),
                ],
                text: """
                    HRV (SDNN) for Apple Health is the middle of \(values.count) of the \(inside.count) beat-to-beat recordings \
                    made fully inside your sleep. Each is the standard deviation of its clean beat-to-beat intervals \
                    (\(beats) clean beats in all), and counts only with at least \(minimumBeats) clean beats and \
                    \(Int(minimumKept * 100)) % of its beats kept. Beats the Loop flagged, beats outside 300–2000 ms and jumps \
                    over 20 % are left out.
                    """
            ),
            computedAt: computedAt
        )
    }

    /// The sample standard deviation (n − 1).
    static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        return (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count - 1)).squareRoot()
    }
}
