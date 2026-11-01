import Foundation
import Testing
import VeselCore
import VeselStorage
@testable import Vesel

/// Journal shows the picked day, and never a day it read before.
@MainActor
struct JournalModelTests {
    @Test func itFollowsThePickedDay() async throws {
        let clock = FixedClock(now: try Date("2026-10-26T09:00:00Z", strategy: .iso8601), timeZone: .gmt)
        let days = DaySelection(clock: clock)
        days.setFirstDay(DayKey(year: 2026, month: 10, day: 1))
        let model = JournalModel(
            database: try AppDatabase.inMemory(), clock: clock, status: SyncStatusStore(defaults: .throwaway()), units: UnitsStore(), days: days
        )
        await observe(model.observe) { model.snapshot != nil }
        #expect(model.isToday)

        let picked = DayKey(year: 2026, month: 10, day: 20)
        days.select(picked)
        #expect(model.day == picked)
        #expect(!model.isToday)
        #expect(model.snapshot == nil)
        #expect(model.nightLine == Formatters.nightEvening(picked, zone: .gmt))

        await observe(model.observe) { model.snapshot != nil }
        #expect(model.snapshot != nil)
    }
}
