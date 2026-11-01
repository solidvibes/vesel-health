import Foundation

/// What cleaning dropped, so every stress number can say how its beats were treated.
public struct PPICleaningCounts: Sendable, Equatable {
    public var intervals = 0
    /// Blocker flag on, or no skin contact.
    public var flagged = 0
    public var outOfRange = 0
    public var jumps = 0

    public var kept: Int { intervals - flagged - outOfRange - jumps }

    public init() {}

    mutating func add(_ other: PPICleaningCounts) {
        intervals += other.intervals
        flagged += other.flagged
        outOfRange += other.outOfRange
        jumps += other.jumps
    }
}

public enum PPICleaning {
    /// Drops beats the band flagged (blocker on, no skin contact), beats outside 300–2000 ms, and beats that
    /// differ by more than 20 % from the previous valid one. The first valid beat has nothing to differ from.
    public static func clean(_ samples: [PPISample]) -> (kept: [PPISample], counts: PPICleaningCounts) {
        var counts = PPICleaningCounts()
        counts.intervals = samples.count
        var kept: [PPISample] = []
        for sample in samples {
            if sample.blocker || !sample.skinContact {
                counts.flagged += 1
            } else if sample.intervalMs < StressThresholds.minimumIntervalMs || sample.intervalMs > StressThresholds.maximumIntervalMs {
                counts.outOfRange += 1
            } else if let previous = kept.last,
                abs(Double(sample.intervalMs - previous.intervalMs)) / Double(previous.intervalMs) > StressThresholds.maximumJump
            {
                counts.jumps += 1
            } else {
                kept.append(sample)
            }
        }
        return (kept, counts)
    }
}
