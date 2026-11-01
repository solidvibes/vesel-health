import Observation
import VeselCore
import VeselStorage

/// What the tabs need beside their screens: the first day with data, which bounds the day picker and the pages, and whether the
/// Loop's battery is low, for the ring.
@MainActor
@Observable
final class RootModel {
    private(set) var batteryLow = false
    private let database: AppDatabase
    private let clock: any VeselClock
    private let days: DaySelection

    init(database: AppDatabase, clock: any VeselClock, days: DaySelection) {
        self.database = database
        self.clock = clock
        self.days = days
    }

    func observeFirstDay() async {
        do {
            for try await first in database.observeFirstDay(zone: clock.timeZone) { days.setFirstDay(first) }
        } catch {
            // Keeps what it last read; it starts again when Vesel comes to the front.
        }
    }

    func observeBattery() async {
        do {
            for try await band in database.observeBand() { batteryLow = band?.isBatteryLow ?? false }
        } catch {
            // Keeps what it last read; it starts again when Vesel comes to the front.
        }
    }
}
