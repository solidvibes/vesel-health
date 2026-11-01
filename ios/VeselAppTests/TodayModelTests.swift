import Foundation
import Testing
import VeselCore
import VeselStorage
@testable import Vesel

/// Today always shows today, shows an alert only once it has gone out, and says so calmly when it can't read.
@MainActor
struct TodayModelTests {
    let now = try! Date("2026-10-26T09:00:00Z", strategy: .iso8601)

    func model(_ database: AppDatabase, clock: MovableClock, failsFirstRead: Bool = false) -> TodayModel {
        TodayModel(
            database: database,
            clock: clock,
            status: SyncStatusStore(defaults: .throwaway()),
            units: UnitsStore(),
            defaults: .throwaway(),
            liveReading: { _ in nil },
            sync: { _ in },
            failsFirstRead: failsFirstRead
        )
    }

    func alert(_ kind: AlertKind, day: DayKey, firedAt: Date) -> AlertEvent {
        let explanation = Explanation(method: "test", version: 1, inputs: [], text: "")
        return AlertEvent(Alert(kind: kind, day: day, title: kind.title, body: "", explanation: explanation), firedAt: firedAt)
    }

    @Test func aSnapshotShowsOnlyForTheDayItWasReadFor() async throws {
        let clock = MovableClock(now: now, timeZone: .gmt)
        let model = model(try AppDatabase.inMemory(), clock: clock)
        await observe(model.observe) { model.snapshot != nil }
        #expect(model.snapshot != nil)

        clock.advance(by: 86_400)
        #expect(model.snapshot == nil)
    }

    @Test func anAlertWaitingFor7ShowsOnlyOnceItHasGoneOut() async throws {
        let database = try AppDatabase.inMemory()
        let clock = MovableClock(now: now, timeZone: .gmt)
        let today = clock.today
        try await database.save(alert(.lowRecovery, day: today, firedAt: now.addingTimeInterval(-3600)))
        try await database.save(alert(.unusualRestingHeartRate, day: today, firedAt: now.addingTimeInterval(3600)))
        let model = model(database, clock: clock)
        await observe(model.observe) { model.snapshot != nil }

        #expect(model.alerts.map(\.kind) == [.lowRecovery])

        clock.advance(by: 2 * 3600)
        #expect(Set(model.alerts.map(\.kind)) == [.lowRecovery, .unusualRestingHeartRate])
    }

    /// Try again restarts the reads, which clears the card.
    @Test func aFailedReadShowsTheCardUntilTryAgainReads() async throws {
        let model = model(try AppDatabase.inMemory(), clock: MovableClock(now: now, timeZone: .gmt), failsFirstRead: true)
        await observe(model.observe) { model.readProblem }
        #expect(model.readProblem)
        #expect(model.snapshot == nil)

        await observe(model.observe) { model.snapshot != nil }
        #expect(!model.readProblem)
        #expect(model.snapshot != nil)
    }
}
