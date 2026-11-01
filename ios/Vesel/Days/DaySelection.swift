import Observation
import VeselCore

/// The one day Journal shows. Today unless the owner picked another; a new day snaps back to today.
@MainActor
@Observable
final class DaySelection {
    private var chosen: DayKey?
    private var chosenOn: DayKey?
    private(set) var firstDay: DayKey?
    /// Bumped at midnight and on a clock or time-zone change, so screens on show read `day` again.
    private var clockChanges = 0
    @ObservationIgnored private let clock: any VeselClock

    init(clock: any VeselClock, chosen: DayKey? = nil) {
        self.clock = clock
        self.chosen = chosen
        chosenOn = chosen.map { _ in clock.today }
    }

    /// The day on screen, held to the first day with data … today. Until the first day is known only today is the limit.
    var day: DayKey {
        _ = clockChanges
        let today = clock.today
        guard let chosen, chosenOn == today else { return today }
        let upper = min(chosen, today)
        return firstDay.map { max(upper, min($0, today)) } ?? upper
    }

    var isToday: Bool { day == clock.today }

    func select(_ day: DayKey) {
        let today = clock.today
        chosen = day >= today ? nil : day
        chosenOn = chosen.map { _ in today }
    }

    /// Whether a day can be picked: first day with data … today; only today while there is no data.
    func canSelect(_ day: DayKey) -> Bool {
        let today = clock.today
        guard let firstDay else { return day == today }
        return day >= firstDay && day <= today
    }

    func clockChanged() {
        clockChanges += 1
    }

    func setFirstDay(_ day: DayKey?) {
        firstDay = day
    }
}

/// Keys a screen's `.task(id:)`: the observation restarts when the value changes, the app comes to the front, or Try again
/// bumps `attempt`.
struct ObserveKey<Value: Equatable>: Equatable {
    let value: Value
    let active: Bool
    var attempt = 0
}
