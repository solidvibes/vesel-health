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

/// Two neighbouring clean beats: the later one's time and how much it differs from the one before, in milliseconds.
public struct PPIPair: Sendable, Equatable {
    public var time: Date
    public var difference: Int

    public init(time: Date, difference: Int) {
        self.time = time
        self.difference = difference
    }
}

public enum PPICleaning {
    /// Drops beats the band flagged (blocker on, no skin contact), beats outside 300–2000 ms, and beats that
    /// differ by more than 20 % from the previous valid one. The first valid beat has nothing to differ from.
    /// `pairs` are the kept beats whose beat right before was kept too: a pair never spans a dropped beat.
    public static func clean(_ samples: [PPISample]) -> (kept: [PPISample], counts: PPICleaningCounts, pairs: [PPIPair]) {
        var counts = PPICleaningCounts()
        counts.intervals = samples.count
        var kept: [PPISample] = []
        var pairs: [PPIPair] = []
        var previousKept = false
        for sample in samples {
            let before = kept.count
            if sample.blocker || !sample.skinContact {
                counts.flagged += 1
            } else if sample.intervalMs < StressThresholds.minimumIntervalMs || sample.intervalMs > StressThresholds.maximumIntervalMs {
                counts.outOfRange += 1
            } else if let previous = kept.last,
                abs(Double(sample.intervalMs - previous.intervalMs)) / Double(previous.intervalMs) > StressThresholds.maximumJump
            {
                counts.jumps += 1
            } else {
                if previousKept, let previous = kept.last {
                    pairs.append(PPIPair(time: sample.time, difference: sample.intervalMs - previous.intervalMs))
                }
                kept.append(sample)
            }
            previousKept = kept.count > before
        }
        return (kept, counts, pairs)
    }
}
