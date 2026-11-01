import Foundation
import GRDB
import Testing
import VeselCore
@testable import VeselStorage

struct AlertStorageTests {
    let berlin = TimeZone(identifier: "Europe/Berlin")!
    let database: AppDatabase

    init() throws {
        database = try AppDatabase.inMemory()
    }

    func day(_ string: String) -> DayKey { DayKey(string)! }

    func event(_ kind: AlertKind, _ day: String, firedAt: String, body: String = "Body") -> AlertEvent {
        AlertEvent(
            Alert(
                kind: kind, day: self.day(day), title: "Title", body: body,
                explanation: Explanation(method: "alerts", version: 1, inputs: [.init(name: "indicator", value: 2, unit: "of 6")], text: "Why.")),
            firedAt: at(firedAt)
        )
    }

    @Test func eightPoorAndUsualNightsBecomeTheFactsTheAlertsUse() async throws {
        // 2026-10-01 to 2026-10-09: indicator 4, then 2 on the last two nights.
        for index in 1...9 {
            let night = DayKey(year: 2026, month: 10, day: index)
            try await database.store(night: night, withRecharge: false)
            try await database.save(
                NightlyRecharge(night: night, recoveryIndicator: index >= 8 ? 2 : 4, recoveryIndicatorSubLevel: 50, meanNightlyRecoveryRMSSD: 40), rawJSON: "{}"
            )
        }
        let clock = FixedClock(now: at("2026-10-09T08:00:00Z"), timeZone: berlin)
        try await MetricsUpdater(database: database, clock: clock).updateAfterSync()

        let facts = try await database.alertFacts(today: day("2026-10-09"), timeZone: berlin)
        #expect(facts.nights.count == 9)
        #expect(facts.earlierNights == 8)
        #expect(facts.nights[day("2026-10-09")]?.status?.indicator == 2)
        #expect(facts.nights[day("2026-10-09")]?.hrv?.value == 40)
        #expect(facts.nights[day("2026-10-09")]?.asleepMinutes == 480)
        #expect(facts.stressDays == 0)
        #expect(facts.stressSpan == nil)
        #expect(facts.settings == AlertSettings())
        #expect(Alerts.due(facts, now: clock.now).map(\.kind) == [.lowRecovery])
    }

    @Test func oneEventPerKindPerDayAndAPendingOneCanChangeOrGo() async throws {
        try await database.save(event(.lowRecovery, "2026-10-09", firedAt: "2026-10-09T06:00:00Z"))
        try await database.save(event(.lowRecovery, "2026-10-09", firedAt: "2026-10-09T06:00:00Z", body: "Changed"))
        #expect(try await database.count("alert_event") == 1)
        #expect(try await database.alertEvents(day: day("2026-10-09")).first?.body == "Changed")
        #expect(try await database.alertEvents(day: day("2026-10-09")).first?.explanation.text == "Why.")

        try await database.deleteAlertEvent(.lowRecovery, day: day("2026-10-09"))
        #expect(try await database.count("alert_event") == 0)
    }

    @Test func factsSayWhatWentOutBeforeAndToday() async throws {
        try await database.save(event(.lowRecovery, "2026-10-05", firedAt: "2026-10-05T07:00:00Z"))
        try await database.save(event(.lowRecovery, "2026-10-07", firedAt: "2026-10-07T07:00:00Z"))
        try await database.save(event(.longHighStress, "2026-10-09", firedAt: "2026-10-09T14:00:00Z"))
        let facts = try await database.alertFacts(today: day("2026-10-09"), timeZone: berlin)
        #expect(facts.lastBefore == [.lowRecovery: day("2026-10-07")])
        #expect(facts.firedToday == [.longHighStress: at("2026-10-09T14:00:00Z")])
    }

    @Test func switchesKeepTheirDefaultUntilChanged() async throws {
        #expect(try await database.alertSettings() == AlertSettings())
        try await database.setAlert(.morningReport, on: true)
        try await database.setAlert(.lowRecovery, on: false)
        let settings = try await database.alertSettings()
        #expect(settings.isOn(.morningReport))
        #expect(!settings.isOn(.lowRecovery))
        #expect(settings.isOn(.longHighStress))
        #expect(try await database.count("setting") == 2)
    }

    @Test func todayCarriesTheWarningsButNotTheMorningReport() async throws {
        try await database.save(event(.morningReport, "2026-10-09", firedAt: "2026-10-09T06:00:00Z"))
        try await database.save(event(.lowRecovery, "2026-10-09", firedAt: "2026-10-09T06:00:00Z"))
        try await database.save(event(.longHighStress, "2026-10-08", firedAt: "2026-10-08T14:00:00Z"))
        let snapshot = try await database.writer.read { try AppDatabase.todaySnapshot($0, day: DayKey("2026-10-09")!, today: DayKey("2026-10-09")!) }
        #expect(snapshot.alerts.map(\.kind) == [.lowRecovery])
    }
}
