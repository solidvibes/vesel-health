import Foundation

/// The average of the 24/7 readings (heart rate, skin temperature) in one 5-minute period (`period` = Unix seconds ÷ 300).
public struct FiveMinuteMean: Sendable, Equatable {
    public static let seconds: Int64 = 300

    public var period: Int64
    public var mean: Double

    public var start: Date { Date(timeIntervalSince1970: Double(period * Self.seconds)) }

    public init(period: Int64, mean: Double) {
        self.period = period
        self.mean = mean
    }
}

/// A day's heart rate: the lowest and highest of that day's 5-minute averages and the average of them all (`hr.dayRange`, version 1).
/// Worked out when the Heart rate page and Journal read, never stored. Per-second bursts during exercise weigh like any other 5 minutes.
public enum DailyHeartRate {
    public static let method = "hr.dayRange"
    public static let version = 1

    /// A day's range as the metric's inputs hold it.
    public struct Range: Sendable, Equatable {
        public var lowest: Double
        public var lowestAt: Date
        public var highest: Double
        public var highestAt: Date
        public var periods: Int

        public init?(_ metric: ComputedMetric) {
            guard metric.explanation.method == DailyHeartRate.method else { return nil }
            func input(_ name: String) -> Double? { metric.explanation.inputs.first { $0.name == name }?.value }
            guard let lowest = input("lowest"), let lowestAt = input("lowestAt"), let highest = input("highest"), let highestAt = input("highestAt"),
                let periods = input("periods")
            else { return nil }
            self.lowest = lowest
            self.lowestAt = Date(timeIntervalSince1970: lowestAt)
            self.highest = highest
            self.highestAt = Date(timeIntervalSince1970: highestAt)
            self.periods = Int(periods)
        }
    }

    /// One metric per day that has a period, oldest first. Days are the calendar days of `zone`.
    /// The value is the day's average; a tie for the lowest or highest goes to the earlier period.
    public static func days(periods: [FiveMinuteMean], zone: TimeZone, computedAt: Date) -> [ComputedMetric] {
        DayBuckets.group(periods, time: \.start, minutes: nil, zone: zone).map { bucket in
            let count = bucket.items.count
            let ordered = bucket.items.sorted { $0.period < $1.period }
            let lowest = ordered.reduce(ordered[0]) { $1.mean < $0.mean ? $1 : $0 }
            let highest = ordered.reduce(ordered[0]) { $1.mean > $0.mean ? $1 : $0 }
            let average = ordered.map(\.mean).reduce(0, +) / Double(count)
            func clock(_ period: FiveMinuteMean) -> String { DayBuckets.clock(period.start, zone: zone) }
            func bpm(_ value: Double) -> String { "\(NumberText.decimal(value, 0)) bpm" }
            let text =
                count == 1
                ? "On this day the Loop's only 5-minute average was \(bpm(lowest.mean)) at \(clock(lowest))."
                : "On this day the Loop's 5-minute averages ran from \(bpm(lowest.mean)) at \(clock(lowest)) to \(bpm(highest.mean)) at \(clock(highest)). Their average was \(bpm(average)), from \(count) five-minute periods."
            return ComputedMetric(
                kind: MetricKind.heartRateDayMean, day: bucket.day, hour: nil, value: average, unit: "bpm",
                explanation: Explanation(
                    method: method, version: version,
                    inputs: [
                        .init(name: "lowest", value: lowest.mean, unit: "bpm"),
                        .init(name: "lowestAt", value: lowest.start.timeIntervalSince1970, unit: "s"),
                        .init(name: "highest", value: highest.mean, unit: "bpm"),
                        .init(name: "highestAt", value: highest.start.timeIntervalSince1970, unit: "s"),
                        .init(name: "periods", value: Double(count), unit: "periods"),
                    ],
                    text: text
                ),
                computedAt: computedAt
            )
        }
    }
}
