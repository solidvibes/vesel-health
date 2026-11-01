import Foundation
import Testing
import VeselCore

/// A stored contributor against a usual of `mean` ± `sd` over 20 nights.
func contributor(_ contributor: Contributor, _ value: Double, mean: Double, sd: Double, night: DayKey) -> ContributorReading {
    ContributorReading(
        ComputedMetric(
            kind: contributor.kind, day: night, hour: nil, value: value, unit: contributor.unit,
            explanation: Explanation(
                method: "recovery", version: 1,
                inputs: [
                    .init(name: "value", value: value, unit: contributor.unit),
                    .init(name: "nights", value: 20, unit: "nights"),
                    .init(name: "usualMean", value: mean, unit: contributor.unit),
                    .init(name: "usualSD", value: sd, unit: contributor.unit),
                ], text: "x"),
            computedAt: at("2026-10-26T06:00:00Z")
        ))!
}

func status(_ indicator: Int, night: DayKey) -> RecoveryStatus {
    RecoveryStatus(NightlyRecharge(night: night, recoveryIndicator: indicator, recoveryIndicatorSubLevel: 50))!
}

func span(minutes: Double, start: String) -> StressSpan {
    StressSpan(
        ComputedMetric(
            kind: MetricKind.stressBusiestSpan, day: day("2026-10-26"), hour: nil, value: minutes, unit: "min",
            explanation: Explanation(
                method: "stress", version: 2,
                inputs: [
                    .init(name: "spanStart", value: at(start).timeIntervalSince1970, unit: "unix s"),
                    .init(name: "spanSeconds", value: 7200, unit: "s"),
                ], text: "Span."),
            computedAt: at("2026-10-26T15:00:00Z")
        ))!
}

func facts(
    today: String = "2026-10-26",
    nights: [DayKey: AlertNight],
    earlier: Int = 20,
    stressDays: Int = 14,
    stressSpan: StressSpan? = nil,
    lastBefore: [AlertKind: DayKey] = [:],
    firedToday: [AlertKind: Date] = [:],
    settings: AlertSettings = AlertSettings()
) -> AlertFacts {
    AlertFacts(
        today: day(today), timeZone: berlin, nights: nights, earlierNights: earlier, stressDays: stressDays,
        stressSpan: stressSpan, lastBefore: lastBefore, firedToday: firedToday, settings: settings
    )
}

struct AlertsTests {
    /// 2026-10-26 09:00 in Berlin (UTC+1).
    let morning = at("2026-10-26T08:00:00Z")

    /// Polar's indicator per night, oldest first, ending on `last`.
    func indicators(_ values: [Int], endingOn last: String = "2026-10-26") -> [DayKey: AlertNight] {
        var nights: [DayKey: AlertNight] = [:]
        for (offset, value) in values.reversed().enumerated() {
            let night = day(last).adding(days: -offset)
            nights[night] = AlertNight(status: status(value, night: night))
        }
        return nights
    }

    /// Runs the alerts once a morning over `nights` from `first` to `last`, as the app would, and returns the days they went out.
    func fired(_ kind: AlertKind, nights: [DayKey: AlertNight], from first: String, to last: String) -> [String] {
        var lastBefore: [AlertKind: DayKey] = [:]
        var days: [String] = []
        var today = day(first)
        while today <= day(last) {
            let known = nights.filter { $0.key <= today }
            let alerts = Alerts.due(
                facts(today: today.description, nights: known, lastBefore: lastBefore), now: today.start(in: berlin).addingTimeInterval(9 * 3600))
            if alerts.contains(where: { $0.kind == kind }) {
                days.append(today.description)
                lastBefore[kind] = today
            }
            today = today.adding(days: 1)
        }
        return days
    }

    @Test func lowRecoveryNeedsTwoPoorNightsInARowAndAlertsOncePerRun() {
        // 20th 4 · 21st 2 · 22nd 2 (fires) · 23rd 2 (same run) · 24th 4 · 25th 1 (one night) · 26th 2 (fires).
        let nights = indicators([4, 2, 2, 2, 4, 1, 2])
        #expect(fired(.lowRecovery, nights: nights, from: "2026-10-20", to: "2026-10-26") == ["2026-10-22", "2026-10-26"])
    }

    @Test func aSingleBadNightNeverAlerts() {
        let nights = indicators([4, 1, 4, 1, 5, 1, 4])
        #expect(fired(.lowRecovery, nights: nights, from: "2026-10-20", to: "2026-10-26").isEmpty)
    }

    @Test func aMissingNightBreaksTheRun() {
        var nights = indicators([2, 2, 2])
        nights[day("2026-10-25")] = nil
        #expect(Alerts.due(facts(nights: nights), now: morning).isEmpty)
    }

    @Test func lowRecoveryAlertsOnceWhileEitherRunGoesOn() {
        // Indicator poor 21st–26th (fires on the 22nd); HRV well below only from the 24th: still the same low stretch.
        var nights = indicators([4, 2, 2, 2, 2, 2, 2], endingOn: "2026-10-26")
        for offset in 0..<3 {
            let night = day("2026-10-26").adding(days: -offset)
            nights[night]?.hrv = contributor(.hrv, 30, mean: 45, sd: 5, night: night)
        }
        #expect(fired(.lowRecovery, nights: nights, from: "2026-10-20", to: "2026-10-26") == ["2026-10-22"])
    }

    @Test func aRunFoundLateInTheEveningAlertsTheNextMorningIfItGoesOn() {
        // Found at 23:00 on the 25th (two poor nights), so not sent; nothing is stored for it.
        let late = facts(today: "2026-10-25", nights: indicators([2, 2], endingOn: "2026-10-25"))
        #expect(AlertTiming.delivery(at: at("2026-10-25T22:00:00Z"), in: berlin) == .skip)
        #expect(Alerts.due(late, now: at("2026-10-25T22:00:00Z")).map(\.kind) == [.lowRecovery])
        // Still poor the next night: the morning's own check sends it.
        #expect(Alerts.due(facts(nights: indicators([2, 2, 2])), now: morning).map(\.kind) == [.lowRecovery])
        // Recovered the next night: nothing to say.
        #expect(Alerts.due(facts(nights: indicators([2, 2, 4])), now: morning).isEmpty)
    }

    @Test func lowRecoveryTellsPolarsWords() throws {
        let alert = try #require(Alerts.due(facts(nights: indicators([1, 2])), now: morning).first)
        #expect(alert.kind == .lowRecovery)
        #expect(alert.day == day("2026-10-26"))
        #expect(alert.title == "Recovery low two nights running")
        #expect(alert.body == "Polar's Nightly Recharge was poor last night and very poor the night before.")
        #expect(alert.explanation.method == "alerts")
        #expect(alert.explanation.version == 1)
        #expect(alert.explanation.inputs.first { $0.name == "indicator" }?.value == 2)
        #expect(alert.explanation.inputs.first { $0.name == "indicatorNightBefore" }?.value == 1)
    }

    @Test func lowRecoveryAlsoFiresOnHRVWellBelowTwoNightsRunning() throws {
        // Usual 45 ± 5 ms: well below is under 35. 33 ms is (45 − 33) ÷ 45 = 26.7 % → "27 %".
        func night(_ string: String, _ hrv: Double) -> (DayKey, AlertNight) {
            (day(string), AlertNight(status: status(4, night: day(string)), hrv: contributor(.hrv, hrv, mean: 45, sd: 5, night: day(string))))
        }
        let both = Dictionary(uniqueKeysWithValues: [night("2026-10-25", 34), night("2026-10-26", 33)])
        let alert = try #require(Alerts.due(facts(nights: both), now: morning).first)
        #expect(alert.body == "HRV 27 % below your usual, two nights running.")
        #expect(alert.explanation.inputs.first { $0.name == "usualMean" }?.value == 45)
        // 35 ms is exactly 2 SD below: not "well below".
        let edge = Dictionary(uniqueKeysWithValues: [night("2026-10-25", 34), night("2026-10-26", 35)])
        #expect(Alerts.due(facts(nights: edge), now: morning).isEmpty)
    }

    @Test func unusualRestingHeartRateTwoNightsAboveTwoSDOrOnceAboveThree() throws {
        // Usual 52 ± 2 bpm: well above is over 56, more than 3 SD is over 58.
        func nights(_ values: [Double]) -> [DayKey: AlertNight] {
            var result: [DayKey: AlertNight] = [:]
            for (offset, value) in values.reversed().enumerated() {
                let night = day("2026-10-26").adding(days: -offset)
                result[night] = AlertNight(restingHeartRate: contributor(.restingHeartRate, value, mean: 52, sd: 2, night: night))
            }
            return result
        }
        let twice = try #require(Alerts.due(facts(nights: nights([57, 57.5])), now: morning).first)
        #expect(twice.kind == .unusualRestingHeartRate)
        #expect(twice.title == "Resting heart rate unusually high")
        #expect(twice.body == "57.5 bpm last night, 5.5 bpm above your usual, two nights running.")
        #expect(twice.explanation.inputs.first { $0.name == "spreads" }?.value == 2.75)

        let once = try #require(Alerts.due(facts(nights: nights([52, 58.4])), now: morning).first)
        #expect(once.body == "58.4 bpm last night, 6.4 bpm above your usual.")

        #expect(Alerts.due(facts(nights: nights([52, 57.9])), now: morning).isEmpty)
        #expect(Alerts.due(facts(nights: nights([52, 56])), now: morning).isEmpty)
    }

    @Test func restingHeartRateAlertsOncePerRun() {
        var nights: [DayKey: AlertNight] = [:]
        for (offset, value) in [52.0, 57, 57, 57, 52, 59].enumerated() {
            let night = day("2026-10-21").adding(days: offset)
            nights[night] = AlertNight(restingHeartRate: contributor(.restingHeartRate, value, mean: 52, sd: 2, night: night))
        }
        #expect(fired(.unusualRestingHeartRate, nights: nights, from: "2026-10-21", to: "2026-10-26") == ["2026-10-23", "2026-10-26"])
    }

    @Test func longHighStressAtFortyFiveMinutesWithinTwoHours() throws {
        let nights = indicators([4])
        let alert = try #require(
            Alerts.due(facts(nights: nights, stressSpan: span(minutes: 52, start: "2026-10-26T12:05:00Z")), now: at("2026-10-26T15:00:00Z")).first)
        #expect(alert.kind == .longHighStress)
        #expect(alert.title == "Long stretch of high stress")
        #expect(alert.body == "52 m of high stress between 13:05 and 15:05.")
        #expect(alert.explanation.text.hasSuffix("Span."))
        #expect(Alerts.due(facts(nights: nights, stressSpan: span(minutes: 44.9, start: "2026-10-26T12:05:00Z")), now: morning).isEmpty)
    }

    @Test func stressNeverAlertsWhileItIsStillLearning() {
        let learning = facts(nights: indicators([4]), stressDays: 6, stressSpan: span(minutes: 90, start: "2026-10-26T12:00:00Z"))
        #expect(Alerts.due(learning, now: morning).isEmpty)
    }

    @Test func nothingInTheFirstSevenNights() {
        let poor = indicators([2, 2])
        #expect(Alerts.due(facts(nights: poor, earlier: 6), now: morning).isEmpty)
        #expect(Alerts.due(facts(nights: poor, earlier: 7), now: morning).count == 1)
    }

    @Test func atMostOnePerKindPerDayButAPendingOneIsCheckedAgain() {
        let poor = indicators([2, 2])
        let sent = facts(nights: poor, firedToday: [.lowRecovery: at("2026-10-26T06:10:00Z")])
        #expect(Alerts.due(sent, now: morning).isEmpty)
        // Found at 05:00, due at 07:00 (06:00 UTC): at 06:30 it is still waiting, so it is due again.
        let pending = facts(nights: poor, firedToday: [.lowRecovery: at("2026-10-26T06:00:00Z")])
        #expect(Alerts.due(pending, now: at("2026-10-26T05:30:00Z")).map(\.kind) == [.lowRecovery])
    }

    @Test func aSwitchedOffAlertNeverFires() {
        let off = facts(nights: indicators([2, 2]), settings: AlertSettings([.lowRecovery: false]))
        #expect(Alerts.due(off, now: morning).isEmpty)
    }

    @Test func onByDefaultButStandUpReminders() {
        let settings = AlertSettings()
        #expect(settings.isOn(.lowRecovery))
        #expect(settings.isOn(.longHighStress))
        #expect(settings.isOn(.unusualRestingHeartRate))
        #expect(settings.isOn(.morningReport))
        #expect(!settings.isOn(.standUp))
    }

    @Test func aNotificationIdNamesItsKindAndNight() throws {
        #expect(AlertIdentifier.make(.morningReport, day("2026-10-26")) == "alert.morningReport.2026-10-26")
        for kind in AlertKind.allCases {
            let parsed = try #require(AlertIdentifier.parse(AlertIdentifier.make(kind, day("2026-10-26"))))
            #expect(parsed.kind == kind)
            #expect(parsed.day == day("2026-10-26"))
        }
        #expect(AlertIdentifier.parse("alert.standUp") == nil)
        #expect(AlertIdentifier.parse("alert.nothing.2026-10-26") == nil)
        #expect(AlertIdentifier.parse("alert.morningReport.yesterday") == nil)
        #expect(AlertIdentifier.parse("") == nil)
    }

    @Test func quietFromTenAtNightUntilSevenInTheMorning() {
        #expect(AlertTiming.delivery(at: at("2026-10-26T06:00:00Z"), in: berlin) == .now)
        #expect(AlertTiming.delivery(at: at("2026-10-26T20:59:59Z"), in: berlin) == .now)
        #expect(AlertTiming.delivery(at: at("2026-10-26T21:00:00Z"), in: berlin) == .skip)
        #expect(AlertTiming.delivery(at: at("2026-10-26T22:59:00Z"), in: berlin) == .skip)
        #expect(AlertTiming.delivery(at: at("2026-10-26T23:30:00Z"), in: berlin) == .at(at("2026-10-27T06:00:00Z")))
        #expect(AlertTiming.delivery(at: at("2026-10-26T05:59:59Z"), in: berlin) == .at(at("2026-10-26T06:00:00Z")))
        // The clocks went back on 25 October: 07:00 that morning is already UTC+1.
        #expect(AlertTiming.delivery(at: at("2026-10-25T03:00:00Z"), in: berlin) == .at(at("2026-10-25T06:00:00Z")))
    }
}
