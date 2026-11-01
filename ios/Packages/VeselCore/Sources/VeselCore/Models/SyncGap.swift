import Foundation

/// Whether a trigger that may repeat often (app opened, band reconnected) should read now. Pure: no band, no database.
public enum SyncGap {
    public static let minimum: TimeInterval = 5 * 60

    /// Opening the app waits only after a read that finished under `minimum` ago, and only once the band has finished the
    /// night (sleep is fetched only after that): a read that was cut off or failed never holds it back. Automatic triggers
    /// wait after a read that started under `minimum` ago and reached the Loop (`runs`, newest first), so a stream of
    /// notices can't turn failing reads into back-to-back downloads, while a try that never found the Loop doesn't hold
    /// back the read when it comes near. A check-in proves the Loop is near, so one also waits after any recent check-in
    /// try: a stream of notices can't start a failing read every few seconds. A time in the future (the clock went back) is
    /// not recent.
    public static func isDue(trigger: SyncTrigger, now: Date, runs: [SyncRun], lastFinishedAt: Date?, nightOver: Bool) -> Bool {
        if trigger == .foreground {
            return !(nightOver && isRecent(lastFinishedAt, now: now))
        }
        if trigger == .bandCheckIn, isRecent(runs.first { $0.trigger == .bandCheckIn }?.startedAt, now: now) {
            return false
        }
        return !isRecent(runs.first { $0.outcome != .unreachable }?.startedAt, now: now)
    }

    private static func isRecent(_ date: Date?, now: Date) -> Bool {
        guard let date else { return false }
        return (0..<minimum).contains(now.timeIntervalSince(date))
    }
}
