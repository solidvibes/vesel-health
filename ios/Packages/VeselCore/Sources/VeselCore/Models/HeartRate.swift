import Foundation

public struct HeartRateSample: Sendable, Equatable {
    public var time: Date
    public var bpm: Int
    public var trigger: HeartRateTrigger

    public init(time: Date, bpm: Int, trigger: HeartRateTrigger) {
        self.time = time
        self.bpm = bpm
        self.trigger = trigger
    }
}

public enum HeartRateTrigger: String, Sendable, Codable {
    case timed, highActivity, lowActivity, manual, unknown
}

extension HeartRateSample {
    /// A longer silence than this breaks the heart-rate line.
    public static let lineGap: TimeInterval = 15 * 60
}

extension Array where Element == HeartRateSample {
    /// The sample closest in time to `date`, if one is within `limit` seconds (a tie goes to the earlier one). Needs the samples in time order.
    public func nearest(to date: Date, within limit: TimeInterval) -> HeartRateSample? {
        var low = 0
        var high = count
        while low < high {
            let mid = (low + high) / 2
            if self[mid].time < date { low = mid + 1 } else { high = mid }
        }
        let candidates = [low - 1, low].filter { indices.contains($0) }.map { self[$0] }
        let best = candidates.min { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) }
        return best.flatMap { abs($0.time.timeIntervalSince(date)) <= limit ? $0 : nil }
    }
}
