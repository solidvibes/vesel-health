import Foundation
import VeselCore

extension UserDefaults {
    /// A suite of its own, so nothing leaks between tests or into Simulator runs.
    static func throwaway() -> UserDefaults {
        UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    }
}

/// A clock the test moves by hand.
final class MovableClock: VeselClock, @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date
    let timeZone: TimeZone

    init(now: Date, timeZone: TimeZone) {
        _now = now
        self.timeZone = timeZone
    }

    var now: Date { lock.withLock { _now } }

    func advance(by interval: TimeInterval) {
        lock.withLock { _now = _now.addingTimeInterval(interval) }
    }
}

/// Waits for `condition`, for work started in its own task. Gives up after a minute, so a broken test fails instead of hanging.
@MainActor
func waitUntil(_ condition: () async -> Bool) async {
    let deadline = ContinuousClock.now + .seconds(60)
    while await !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(5)) }
}

/// Runs one of a model's observations until `done` holds, then stops it, as leaving the screen does.
@MainActor
func observe(_ observation: @escaping @MainActor () async -> Void, until done: () -> Bool) async {
    let task = Task { await observation() }
    await waitUntil { done() }
    task.cancel()
    await task.value
}
