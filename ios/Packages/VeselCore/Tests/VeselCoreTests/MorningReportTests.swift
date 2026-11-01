import Foundation
import Testing
import VeselCore

struct MorningReportTests {
    let today = day("2026-10-26")
    let morning = at("2026-10-26T06:30:00Z")

    func night(asleep: Double? = 432, indicator: Int? = 4) -> [DayKey: AlertNight] {
        [today: AlertNight(status: indicator.map { status($0, night: today) }, asleepMinutes: asleep)]
    }

    let on = AlertSettings([.morningReport: true])

    @Test func onUntilTheOwnerTurnsItOff() {
        #expect(MorningReport.due(facts(nights: night()), now: morning) != nil)
        #expect(MorningReport.due(facts(nights: night(), settings: AlertSettings([.morningReport: false])), now: morning) == nil)
    }

    @Test func lastNightInOneLine() throws {
        let report = try #require(MorningReport.due(facts(nights: night(), settings: on), now: morning))
        #expect(report.kind == .morningReport)
        #expect(report.day == today)
        #expect(report.title == "Last night")
        #expect(report.body == "Slept 7 h 12 m · Recharge OK")
        #expect(report.explanation.inputs.first { $0.name == "asleep" }?.value == 432)
    }

    @Test func waitsUntilSleepAndNightlyRechargeAreBothStored() {
        #expect(MorningReport.due(facts(nights: night(indicator: nil), settings: on), now: morning) == nil)
        #expect(MorningReport.due(facts(nights: night(asleep: nil), settings: on), now: morning) == nil)
        #expect(MorningReport.due(facts(nights: [:], settings: on), now: morning) == nil)
    }

    @Test func oncePerNight() {
        let sent = facts(nights: night(), firedToday: [.morningReport: at("2026-10-26T06:00:00Z")], settings: on)
        #expect(MorningReport.due(sent, now: morning) == nil)
    }

    @Test func comesFromTheFirstNightOn() {
        #expect(MorningReport.due(facts(nights: night(), earlier: 0, settings: on), now: morning) != nil)
    }
}
