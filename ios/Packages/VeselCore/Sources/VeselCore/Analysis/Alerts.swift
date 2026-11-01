import Foundation

public enum AlertKind: String, Sendable, CaseIterable, Codable {
    case lowRecovery, longHighStress, unusualRestingHeartRate, morningReport, standUp

    /// The switch's label in Loop & settings.
    public var title: String {
        switch self {
        case .lowRecovery: "Low recovery"
        case .longHighStress: "Long high stress"
        case .unusualRestingHeartRate: "Unusual resting heart rate"
        case .morningReport: "Morning sleep report"
        case .standUp: "Stand-up reminders"
        }
    }

    /// Everything but stand-up reminders is on until the owner turns it off.
    public var isOnByDefault: Bool { isWarning || self == .morningReport }

    /// "Something's off": every kind but the morning report and stand-up reminders.
    public var isWarning: Bool { self != .morningReport && self != .standUp }
}

/// A notification's id: `alert.<kind>.<day>`. A tap goes where the id says.
public enum AlertIdentifier {
    public static func make(_ kind: AlertKind, _ day: DayKey) -> String {
        "alert.\(kind.rawValue).\(day)"
    }

    /// The kind and day of an id made by `make`; nil for anything else (a stand-up reminder's `alert.standUp`).
    public static func parse(_ identifier: String) -> (kind: AlertKind, day: DayKey)? {
        let parts = identifier.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "alert",
            let kind = AlertKind(rawValue: String(parts[1])), let day = DayKey(String(parts[2]))
        else { return nil }
        return (kind, day)
    }
}

/// One notification Vesel wants to send, with why. Its title and body are all the notification shows.
public struct Alert: Sendable, Equatable {
    public var kind: AlertKind
    public var day: DayKey
    public var title: String
    public var body: String
    public var explanation: Explanation

    public init(kind: AlertKind, day: DayKey, title: String, body: String, explanation: Explanation) {
        self.kind = kind
        self.day = day
        self.title = title
        self.body = body
        self.explanation = explanation
    }
}

/// An alert as stored: when it went out, or is due to (07:00 after quiet hours).
public struct AlertEvent: Sendable, Equatable {
    public var kind: AlertKind
    public var day: DayKey
    public var firedAt: Date
    public var title: String
    public var body: String
    public var explanation: Explanation

    public init(_ alert: Alert, firedAt: Date) {
        kind = alert.kind
        day = alert.day
        self.firedAt = firedAt
        title = alert.title
        body = alert.body
        explanation = alert.explanation
    }
}

/// Which alerts are on. A kind the owner never touched keeps its default.
public struct AlertSettings: Sendable, Equatable {
    public var values: [AlertKind: Bool]

    public init(_ values: [AlertKind: Bool] = [:]) {
        self.values = values
    }

    public func isOn(_ kind: AlertKind) -> Bool { values[kind] ?? kind.isOnByDefault }
}

/// What alerts need to know about one night.
public struct AlertNight: Sendable, Equatable {
    public var status: RecoveryStatus?
    public var hrv: ContributorReading?
    public var restingHeartRate: ContributorReading?
    public var asleepMinutes: Double?

    public init(status: RecoveryStatus? = nil, hrv: ContributorReading? = nil, restingHeartRate: ContributorReading? = nil, asleepMinutes: Double? = nil) {
        self.status = status
        self.hrv = hrv
        self.restingHeartRate = restingHeartRate
        self.asleepMinutes = asleepMinutes
    }
}

/// Everything alerts are decided from, read from the database in one go.
public struct AlertFacts: Sendable, Equatable {
    public var today: DayKey
    public var timeZone: TimeZone
    /// The nights up to today that have numbers.
    public var nights: [DayKey: AlertNight]
    /// Nights with data in the 28 days before today.
    public var earlierNights: Int
    /// Earlier days with enough stress readings; stress is trustworthy from 7.
    public var stressDays: Int
    public var stressSpan: StressSpan?
    /// The latest day each kind went out before today.
    public var lastBefore: [AlertKind: DayKey]
    /// Today's alerts: when each went out, or is due to.
    public var firedToday: [AlertKind: Date]
    public var settings: AlertSettings

    public init(
        today: DayKey, timeZone: TimeZone, nights: [DayKey: AlertNight], earlierNights: Int, stressDays: Int,
        stressSpan: StressSpan?, lastBefore: [AlertKind: DayKey], firedToday: [AlertKind: Date], settings: AlertSettings
    ) {
        self.today = today
        self.timeZone = timeZone
        self.nights = nights
        self.earlierNights = earlierNights
        self.stressDays = stressDays
        self.stressSpan = stressSpan
        self.lastBefore = lastBefore
        self.firedToday = firedToday
        self.settings = settings
    }

    /// Already out today: one per kind per day.
    func wentOut(_ kind: AlertKind, by now: Date) -> Bool {
        firedToday[kind].map { $0 <= now } ?? false
    }
}

/// When something has been off for a while (`alerts`, version 1). The rules are in `docs/how-it-works/alerts.md`.
public enum Alerts {
    public static let method = "alerts"
    public static let version = 1

    /// No alert before this many earlier nights: Vesel is still learning your normal.
    public static let minimumNights = 7
    /// Polar's indicator at or below this is poor or very poor.
    public static let poorIndicator = 2
    public static let streakNights = 2
    /// Resting heart rate this many SD above usual alerts on its own, without a second night.
    public static let restingOnceSpreads = 3.0
    public static let highStressMinutes = 45.0

    /// The alerts that should be out today and aren't yet: switched on, past the learning nights, and not already
    /// sent for the same streak. A pending one (due at 07:00) is returned again while it still holds.
    public static func due(_ facts: AlertFacts, now: Date) -> [Alert] {
        guard facts.earlierNights >= minimumNights else { return [] }
        var result: [Alert] = []
        func open(_ kind: AlertKind) -> Bool { facts.settings.isOn(kind) && !facts.wentOut(kind, by: now) }
        if open(.lowRecovery), let alert = lowRecovery(facts) { result.append(alert) }
        if open(.unusualRestingHeartRate), let alert = unusualRestingHeartRate(facts) { result.append(alert) }
        if open(.longHighStress), let alert = longHighStress(facts) { result.append(alert) }
        return result
    }

    /// Nights in a row, from today back, for which `holds` is true. A night without numbers ends the run.
    static func streak(_ facts: AlertFacts, _ holds: (AlertNight) -> Bool) -> [DayKey] {
        var nights: [DayKey] = []
        var night = facts.today
        while let found = facts.nights[night], holds(found) {
            nights.append(night)
            night = night.adding(days: -1)
        }
        return nights
    }

    /// This run of nights already alerted on one of its days.
    static func alerted(_ kind: AlertKind, during nights: [DayKey], _ facts: AlertFacts) -> Bool {
        facts.lastBefore[kind].map(nights.contains) ?? false
    }

    static func lowRecovery(_ facts: AlertFacts) -> Alert? {
        let poor = streak(facts) { ($0.status?.indicator ?? .max) <= poorIndicator }
        let low = streak(facts) { $0.hrv?.verdict == .wellBelow }
        // Either run already alerted: it is the same low stretch.
        guard !alerted(.lowRecovery, during: poor + low, facts) else { return nil }
        if poor.count >= streakNights,
            let tonight = facts.nights[poor[0]]?.status, let before = facts.nights[poor[1]]?.status
        {
            return Alert(
                kind: .lowRecovery, day: facts.today,
                title: "Recovery low two nights running",
                body: "Polar's Nightly Recharge was \(tonight.word) last night and \(before.word) the night before.",
                explanation: Explanation(
                    method: method, version: version,
                    inputs: [
                        .init(name: "indicator", value: Double(tonight.indicator), unit: "of 6"),
                        .init(name: "indicatorNightBefore", value: Double(before.indicator), unit: "of 6"),
                        .init(name: "nightsInARow", value: Double(poor.count), unit: "nights"),
                    ],
                    text:
                        "Polar's Nightly Recharge was \(poorIndicator) of 6 or lower (poor or very poor) \(poor.count) nights in a row: \(tonight.indicator) last night, \(before.indicator) the night before. One run of nights alerts once."
                )
            )
        }
        guard low.count >= streakNights,
            let hrv = facts.nights[low[0]]?.hrv, let range = hrv.range, range.mean > 0
        else { return nil }
        let percent = (range.mean - hrv.value) / range.mean * 100
        return Alert(
            kind: .lowRecovery, day: facts.today,
            title: "Recovery low two nights running",
            body: "HRV \(NumberText.decimal(percent, 0)) % below your usual, two nights running.",
            explanation: Explanation(
                method: method, version: version,
                inputs: [
                    .init(name: "hrv", value: hrv.value, unit: "ms"),
                    .init(name: "usualMean", value: range.mean, unit: "ms"),
                    .init(name: "usualSD", value: range.sd, unit: "ms"),
                    .init(name: "nightsInARow", value: Double(low.count), unit: "nights"),
                ],
                text:
                    "HRV was more than 2 standard deviations below your usual \(low.count) nights in a row. Last night \(hrv.valueText()) against a usual of \(Contributor.hrv.text(range.mean)), \(NumberText.decimal(percent, 0)) % lower. One run of nights alerts once."
            )
        )
    }

    static func unusualRestingHeartRate(_ facts: AlertFacts) -> Alert? {
        let high = streak(facts) { $0.restingHeartRate?.verdict == .wellAbove }
        guard let tonight = facts.nights[facts.today]?.restingHeartRate, let range = tonight.range, let spreads = tonight.spreads,
            high.count >= streakNights || (high.count == 1 && spreads > restingOnceSpreads),
            !alerted(.unusualRestingHeartRate, during: high, facts)
        else { return nil }
        let difference = tonight.value - range.mean
        let running = high.count >= streakNights ? ", two nights running" : ""
        return Alert(
            kind: .unusualRestingHeartRate, day: facts.today,
            title: "Resting heart rate unusually high",
            body: "\(tonight.valueText()) last night, \(Contributor.restingHeartRate.text(difference)) above your usual\(running).",
            explanation: Explanation(
                method: method, version: version,
                inputs: [
                    .init(name: "restingHeartRate", value: tonight.value, unit: "bpm"),
                    .init(name: "usualMean", value: range.mean, unit: "bpm"),
                    .init(name: "usualSD", value: range.sd, unit: "bpm"),
                    .init(name: "spreads", value: spreads, unit: "SD"),
                    .init(name: "nightsInARow", value: Double(high.count), unit: "nights"),
                ],
                text:
                    "Resting heart rate alerts when it is more than 2 standard deviations above your usual two nights in a row, or more than 3 once. Last night \(tonight.valueText()), \(NumberText.decimal(spreads, 1)) standard deviations above your usual of \(Contributor.restingHeartRate.text(range.mean)), \(high.count) night\(high.count == 1 ? "" : "s") in a row."
            )
        )
    }

    static func longHighStress(_ facts: AlertFacts) -> Alert? {
        guard facts.stressDays >= StressThresholds.minimumDays, let span = facts.stressSpan, span.minutes >= highStressMinutes else { return nil }
        let from = clockText(span.start, facts.timeZone)
        let to = clockText(span.end, facts.timeZone)
        return Alert(
            kind: .longHighStress, day: facts.today,
            title: "Long stretch of high stress",
            body: "\(DurationText.hoursMinutes(minutes: span.minutes)) of high stress between \(from) and \(to).",
            explanation: Explanation(
                method: method, version: version,
                inputs: [
                    .init(name: "highMinutes", value: span.minutes, unit: "min"),
                    .init(name: "spanStart", value: span.start.timeIntervalSince1970, unit: "unix s"),
                ],
                text:
                    "Long high stress alerts at \(NumberText.decimal(highStressMinutes, 0)) minutes or more of high stress within 2 hours. Between \(from) and \(to) there were \(DurationText.hoursMinutes(minutes: span.minutes)). \(span.explanation.text)"
            )
        )
    }

    static func clockText(_ date: Date, _ zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0
        return "\(hour < 10 ? "0" : "")\(hour):\(minute < 10 ? "0" : "")\(minute)"
    }
}

/// When a notification may go out: nothing from 22:00 to 07:00.
public enum AlertDelivery: Sendable, Equatable {
    case now
    /// Found between midnight and 07:00: held until 07:00 that morning, and dropped if no longer true by then.
    case at(Date)
    /// Found between 22:00 and midnight: by 07:00 it is about yesterday, so it isn't sent.
    case skip
}

public enum AlertTiming {
    public static let quietFrom = 22
    public static let quietUntil = 7

    public static func delivery(at now: Date, in zone: TimeZone) -> AlertDelivery {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let hour = calendar.component(.hour, from: now)
        if hour >= quietFrom { return .skip }
        if hour < quietUntil {
            return .at(calendar.date(bySettingHour: quietUntil, minute: 0, second: 0, of: now)!)
        }
        return .now
    }
}
