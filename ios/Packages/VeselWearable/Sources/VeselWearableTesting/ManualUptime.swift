#if VESEL_FAKE_BAND
import Foundation

/// A read's time (`BandSync(uptime:)`) that moves only when the fake band takes time, so a busy test machine never makes
/// a band call look stuck. It counts how often it is read, so the fake band knows when the read's watchdog has looked.
public final class ManualUptime: @unchecked Sendable {
    private let lock = NSLock()
    private let start = ContinuousClock.now
    private var passed: Duration = .zero
    private var reads = 0

    public init() {}

    public var now: ContinuousClock.Instant {
        lock.withLock {
            reads += 1
            return start + passed
        }
    }

    var timesRead: Int { lock.withLock { reads } }

    /// Returns how often it had been read when it moved.
    func advance(by duration: Duration) -> Int {
        lock.withLock {
            passed += duration
            return reads
        }
    }
}
#endif
