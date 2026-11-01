import Foundation

/// One day's steps by wall-clock hour, from the band's per-minute step samples.
public struct HourlySteps: Equatable, Sendable {
    public struct Sample: Decodable, Equatable, Sendable {
        /// Band wall time: "2026-10-26T06:10:00+01:00".
        public var time: String
        public var steps: Int

        public init(time: String, steps: Int) {
            self.time = time
            self.steps = steps
        }
    }

    public struct Hour: Equatable, Identifiable, Sendable {
        public let hour: Int
        public let steps: Int
        public var id: Int { hour }

        public init(hour: Int, steps: Int) {
            self.hour = hour
            self.steps = steps
        }
    }

    /// Hours with steps, oldest first; an hour with none has no entry.
    public let hours: [Hour]

    public var isEmpty: Bool { hours.isEmpty }

    /// Each sample counts in the hour on its own wall clock (00 to 23), so a day of 23 or 25 hours still has 24 bars: the hour
    /// that repeats when the clocks go back is one bar, the hour that is skipped has none. Samples dated another day are left out.
    public init(day: DayKey, samples: [Sample]) {
        let prefix = day.description + "T"
        var totals: [Int: Int] = [:]
        for sample in samples where sample.steps > 0 && sample.time.hasPrefix(prefix) {
            let digits = sample.time.dropFirst(prefix.count).prefix(2)
            guard digits.count == 2, let hour = Int(digits), (0..<24).contains(hour) else { continue }
            totals[hour, default: 0] += sample.steps
        }
        hours = totals.sorted { $0.key < $1.key }.map { Hour(hour: $0.key, steps: $0.value) }
    }
}
