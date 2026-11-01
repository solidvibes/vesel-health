import Foundation
import VeselCore

let berlin = TimeZone(identifier: "Europe/Berlin")!

func at(_ iso: String) -> Date {
    try! Date(iso, strategy: .iso8601)
}

func day(_ string: String) -> DayKey {
    DayKey(string)!
}

/// A clock the test moves by hand.
final class TestClock: VeselClock, @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date
    let timeZone: TimeZone

    init(_ iso: String, timeZone: TimeZone = berlin) {
        _now = at(iso)
        self.timeZone = timeZone
    }

    var now: Date { lock.withLock { _now } }

    func set(_ iso: String) {
        lock.withLock { _now = at(iso) }
    }
}

/// Waits for `condition`, for work started in its own task. Gives up after a minute, so a broken test fails instead of hanging.
func waitUntil(_ condition: () async -> Bool) async {
    let deadline = ContinuousClock.now + .seconds(60)
    while await !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(5)) }
}
