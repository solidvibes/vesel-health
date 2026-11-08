import Foundation

/// The Loop answers "busy" to every read and a restart is the fix. A workout makes it busy for a while too, so it counts as
/// stuck only after every read that reached it for `grace` came back busy.
public enum LoopStuck {
    public static let grace: TimeInterval = 2 * 3600

    /// When the busy streak began; nil when the Loop isn't stuck. `runs` newest first. Reads that didn't reach the Loop, or
    /// were cut off, neither start nor end a streak.
    public static func since(_ runs: [SyncRun], now: Date) -> Date? {
        var first: Date?
        for run in runs where run.outcome != nil && run.outcome != .unreachable {
            guard run.isLoopBusy else { break }
            first = run.startedAt
        }
        guard let first, now.timeIntervalSince(first) >= grace else { return nil }
        return first
    }
}

extension SyncRun {
    /// The Loop answered "busy" (Polar's error 202).
    public var isLoopBusy: Bool { detail?.hasPrefix(SyncDetail.loopBusy) == true }
}
