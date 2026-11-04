import Foundation
import Observation
import SwiftUI
import VeselCore
import VeselStorage

/// How Body's cards are grouped, with the one line that says what the group is.
enum BodyGroup: CaseIterable {
    case daily, movement, overnight

    var title: String {
        switch self {
        case .daily: "Recovery, sleep and stress"
        case .movement: "Movement"
        case .overnight: "Overnight"
        }
    }

    var line: String {
        switch self {
        case .daily: "Each night's number and your normal around it."
        case .movement: "How much you move each day, and your normal around it."
        case .overnight: "What your Loop measured while you slept."
        }
    }

    var kinds: [TrendKind] {
        switch self {
        case .daily: [.recovery, .sleep, .calm]
        case .movement: [.steps]
        case .overnight: [.hrv, .restingHeartRate, .lowestHeartRate, .breathing, .skinTemperature]
        }
    }
}

/// One number Body follows over time.
enum TrendKind: String, CaseIterable, Hashable {
    case recovery, sleep, calm, steps, hrv, restingHeartRate, lowestHeartRate, breathing, skinTemperature, inBed, efficiency

    init(_ contributor: Contributor) {
        switch contributor {
        case .hrv: self = .hrv
        case .restingHeartRate: self = .restingHeartRate
        case .sleep: self = .sleep
        case .breathing: self = .breathing
        case .skinTemperature: self = .skinTemperature
        }
    }

    var title: String {
        switch self {
        case .recovery: "Recovery"
        case .sleep: "Sleep"
        case .calm: "Stress"
        case .steps: "Steps"
        case .hrv: "HRV"
        case .restingHeartRate: "Resting heart rate"
        case .lowestHeartRate: "Lowest heart rate"
        case .breathing: "Breathing"
        case .skinTemperature: "Skin temperature"
        case .inBed: "In bed"
        case .efficiency: "Efficiency"
        }
    }

    /// What the card's title explains.
    var term: Term {
        switch self {
        case .recovery: .recovery
        case .sleep: .sleepTime
        case .calm: .highStress
        case .steps: .steps
        case .hrv: .hrv
        case .restingHeartRate: .restingHeartRate
        case .lowestHeartRate: .lowestHeartRate
        case .breathing: .breathing
        case .skinTemperature: .skinTemperature
        case .inBed: .timeInBed
        case .efficiency: .sleepEfficiency
        }
    }

    var metricKind: String {
        switch self {
        case .recovery: MetricKind.recoveryStatus
        case .sleep: Contributor.sleep.kind
        case .calm: MetricKind.stressHighMinutes
        case .steps: MetricKind.steps
        case .hrv: Contributor.hrv.kind
        case .restingHeartRate: Contributor.restingHeartRate.kind
        case .lowestHeartRate: MetricKind.sleepLowestHeartRate
        case .breathing: Contributor.breathing.kind
        case .skinTemperature: Contributor.skinTemperature.kind
        case .inBed: MetricKind.sleepInBed
        case .efficiency: MetricKind.sleepEfficiency
        }
    }

    /// What the thing's own pages read: In bed and Efficiency only their series, the others Body's list.
    var readKinds: [String] { self == .inBed || self == .efficiency ? [metricKind] : TrendsSnapshot.kinds }

    var color: Color {
        switch self {
        case .sleep, .inBed, .efficiency: Theme.Palette.sleep
        case .calm: Theme.Palette.stress
        case .steps: Theme.Palette.mutedText
        default: Theme.Palette.recovery
        }
    }

    /// The shaded normal: steps are drawn in muted bars, so their band takes the accent to stay apart from them.
    var bandColor: Color { self == .steps ? Theme.Palette.accent : color }

    /// Bars for days or nights that either have a number or don't, drawn from 0; lines for measures that follow you night after night.
    var isBars: Bool { self == .calm || self == .steps || self == .sleep || self == .inBed }

    /// Whether the number is a whole day's, for the wording "a day"; sleep is bars but still a night's.
    var isPerDay: Bool { self == .calm || self == .steps }

    var contributor: Contributor? {
        switch self {
        case .hrv: .hrv
        case .restingHeartRate: .restingHeartRate
        case .breathing: .breathing
        case .sleep: .sleep
        case .skinTemperature: .skinTemperature
        case .recovery, .calm, .steps, .lowestHeartRate, .inBed, .efficiency: nil
        }
    }

    /// Whether the normal is worked out from your own nights, so it needs 7 of them first.
    var learnsItsNormal: Bool { contributor != nil || [.lowestHeartRate, .steps, .inBed, .efficiency].contains(self) }

    /// A value as the screens write it, in real units.
    func format(_ value: Double, units: Units) -> String {
        switch self {
        case .lowestHeartRate: "\(Formatters.whole(value)) bpm"
        case .calm: DurationText.hoursMinutes(minutes: value)
        case .steps: "\(Formatters.steps(Int(value.rounded()))) steps"
        case .inBed: DurationText.hoursMinutes(minutes: value)
        case .efficiency: "\(Formatters.whole(value)) %"
        case .recovery: "\(Formatters.whole(value)) of 6"
        default: contributor?.text(value, units: units) ?? "—"
        }
    }

    /// What the chart's axis is in. Sleep is drawn in hours, recovery on Polar's 1 to 6.
    func axisLabel(units: Units) -> String {
        switch self {
        case .recovery: "Polar's 1–6"
        case .hrv: "ms"
        case .restingHeartRate, .lowestHeartRate: "bpm"
        case .skinTemperature: units.temperatureUnit
        case .breathing: "breaths/min"
        case .sleep, .inBed: "hours"
        case .efficiency: "%"
        case .calm: "minutes"
        case .steps: "steps"
        }
    }

    /// The value as the chart draws it.
    func plotted(_ value: Double, units: Units) -> Double {
        switch self {
        case .sleep, .inBed: value / 60
        case .skinTemperature: units.temperature(celsius: value)
        default: value
        }
    }

    func text(_ metric: ComputedMetric, units: Units) -> String {
        switch self {
        case .recovery: RecoveryStatus(metric)?.verdict ?? "—"
        default: format(metric.value, units: units)
        }
    }
}

/// One night (one day, for calm and steps) with a number, and the normal it is judged against; nil while that is still being learned.
struct TrendNight: Equatable {
    let metric: ComputedMetric
    /// In the metric's own units, before the chart's: recovery on Polar's 1 to 6, sleep and calm in minutes, steps as counted, skin temperature in °C.
    let value: Double
    /// The normal in the same terms: for each night, low…high of the 28 nights before it.
    let normal: ClosedRange<Double>?
    /// How the number and its normal were worked out: the metric's own, except for sleep, whose normal is the sleep line's.
    let explanation: Explanation
    /// Where the night stands against its normal; nil while that is being learned, and for bars.
    let mark: NormalMark?
    /// How a normal worked out here from the 28 nights before it was made (the lowest heart rate's); the others' is in `explanation`.
    let normalExplanation: Explanation?
}

/// What a signal page's picture draws and says for one night: where the normal and the night sit, and the words.
struct NightPicture: Equatable {
    let scale: LineScale
    /// Nil where the thing has no mark (In bed): the dot and value show in the data colour.
    let mark: NormalMark?
    let value: String
    let low: String
    let high: String
    let spoken: String
}

/// A night's dot or bar, and its normal as the band behind it (`low`…`high`).
struct TrendPoint: Identifiable, Equatable {
    let day: DayKey
    let start: Date
    let end: Date
    let value: Double
    var low: Double?
    var high: Double?
    /// The day isn't over: its bar is drawn lighter.
    var isPartial = false
    /// Against its normal; nil while learning, for bars and where the signal has no mark.
    var mark: NormalMark?
    var id: Date { start }

    var isOutsideNormal: Bool {
        guard let low, let high else { return false }
        return value < low || value > high
    }
}

/// A label on a chart's date axis.
struct TrendTick: Equatable {
    let date: Date
    let label: String
}

/// Runs of points that touch: a missing night breaks the line instead of being drawn across.
extension Array where Element == TrendPoint {
    var runs: [[TrendPoint]] {
        var result: [[TrendPoint]] = []
        for point in self {
            if let last = result.last?.last, last.end >= point.start {
                result[result.count - 1].append(point)
            } else {
                result.append([point])
            }
        }
        return result
    }
}

@MainActor
@Observable
final class BodyModel {
    let period: PagePeriod
    private(set) var isReady = false
    private(set) var nights: [TrendKind: [TrendNight]] = [:]
    /// Heart fitness for the month before this one; nil until read, and without a profile.
    private(set) var fitness: FitnessOutcome?
    /// A VO2max another device measured (About you), shown beside Vesel's estimate; never part of it.
    private(set) var measuredVO2max: Double?
    private var series: [String: [ComputedMetric]]?
    private var dayLines: [DayKey: DayLines]?
    private let reads = ReadProblem()
    private let database: AppDatabase
    private let clock: any VeselClock
    private let unitsStore: UnitsStore
    private let endingOn: DayKey?
    private let kinds: [String]

    /// `endingOn` nil means today. `kinds` are the metric kinds read: Body's list unless the page shows others.
    init(
        database: AppDatabase, clock: any VeselClock, units: UnitsStore, period: PagePeriod, endingOn: DayKey? = nil,
        kinds: [String] = TrendsSnapshot.kinds
    ) {
        self.kinds = kinds
        self.database = database
        self.clock = clock
        unitsStore = units
        self.period = period
        self.endingOn = endingOn
    }

    var zone: TimeZone { clock.timeZone }
    var end: DayKey { endingOn ?? clock.today }
    var today: DayKey { clock.today }
    var endsToday: Bool { end == today }
    var units: Units { unitsStore.units }
    /// A read failed; the screen shows its one "Couldn't show this" card.
    var readProblem: Bool { reads.isShown }

    /// Steps alone don't start Body: it begins with the first night.
    var hasNothing: Bool { nights.filter { $0.key != .steps }.values.allSatisfy(\.isEmpty) }

    var firstDay: DayKey { PeriodWindow.first(endingOn: end, period: period) }

    /// Every chart draws the whole period: from the first day's start to the end of the last day.
    var domain: ClosedRange<Date> { firstDay.start(in: zone)...end.adding(days: 1).start(in: zone) }

    static func midday(_ day: DayKey, zone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day.start(in: zone)) ?? day.start(in: zone)
    }

    private func midday(_ day: DayKey) -> Date { Self.midday(day, zone: zone) }

    /// The date labels of a chart: every day's short weekday on a week, every 7th day back from the last (the last itself has no room) on 4 weeks, the 1st of each month on 3 months.
    var ticks: [TrendTick] { Self.ticks(period: period, end: end, zone: zone) }

    static func ticks(period: PagePeriod, end: DayKey, zone: TimeZone) -> [TrendTick] {
        let days = PeriodWindow.days(endingOn: end, period: period)
        switch period {
        case .day, .week:
            return days.map {
                TrendTick(date: midday($0, zone: zone), label: $0.start(in: zone).formatted(Date.FormatStyle(timeZone: zone).weekday(.abbreviated)))
            }
        case .month:
            return days.enumerated().filter { $0.offset < period.days - 1 && (period.days - 1 - $0.offset) % 7 == 0 }
                .map { TrendTick(date: midday($0.element, zone: zone), label: Formatters.shortDay($0.element, zone: zone)) }
        case .quarter:
            return days.filter { $0.day == 1 }.map {
                TrendTick(date: $0.start(in: zone), label: $0.start(in: zone).formatted(Date.FormatStyle(timeZone: zone).month(.abbreviated)))
            }
        }
    }

    /// The nights of `kind` inside the shown range.
    func inRange(_ kind: TrendKind) -> [TrendNight] {
        (nights[kind] ?? []).filter { $0.metric.day >= firstDay && $0.metric.day <= end }
    }

    func latest(_ kind: TrendKind) -> TrendNight? { inRange(kind).last }

    func points(_ kind: TrendKind) -> [TrendPoint] {
        let units = units
        return inRange(kind).map { night in
            let day = night.metric.day
            let start = kind.isBars ? day.start(in: zone) : (day == today ? min(midday(day), clock.now) : midday(day))
            let end = kind.isBars ? day.adding(days: 1).start(in: zone) : midday(day.adding(days: 1))
            return TrendPoint(
                day: day, start: start, end: end, value: kind.plotted(night.value, units: units),
                low: night.normal.map { kind.plotted($0.lowerBound, units: units) },
                high: night.normal.map { kind.plotted($0.upperBound, units: units) },
                isPartial: kind == .steps && day == today, mark: night.mark
            )
        }
    }

    /// Before the latest night has a normal: the median so far, in the chart's units, and how many earlier nights that rests on.
    func settling(_ kind: TrendKind) -> Settling? {
        guard kind.learnsItsNormal, let latest = latest(kind), latest.normal == nil else { return nil }
        let found = PersonalRange.settling(of: (nights[kind] ?? []).map(\.metric).filter { $0.day <= latest.metric.day })
        return Settling(median: found.map { kind.plotted($0.median, units: units) }, earlierNights: found?.earlierNights ?? 0)
    }

    /// While the latest night has no normal yet: the learning wording.
    func learningNote(_ kind: TrendKind) -> String? {
        settling(kind).map { kind == .steps ? LearningText.usualDays($0.earlierNights) : LearningText.nights($0.earlierNights) }
    }

    /// Under the Steps card's chart once it has a normal: the normal, and why today's bar is lighter.
    func stepsNote(_ kind: TrendKind) -> String? {
        guard kind == .steps, let normal = normalText(kind) else { return nil }
        return "Your normal \(normal)." + (latest(kind)?.metric.day == today ? " Today's bar is lighter: the day isn't over." : "")
    }

    /// "34–52 ms", in the units of the value; for the latest night's normal.
    func normalText(_ kind: TrendKind) -> String? {
        guard let latest = latest(kind), let normal = latest.normal else { return nil }
        let units = units
        if kind == .recovery { return "OK or better" }
        if kind == .calm { return "up to \(kind.format(normal.upperBound, units: units))" }
        if kind == .steps { return "\(Formatters.steps(hundreds(normal.lowerBound)))–\(Formatters.steps(hundreds(normal.upperBound))) a day" }
        let (low, high) = normalEnds(kind, normal)
        return "\(low)–\(high)"
    }

    /// The ends of a normal as written, the unit only on the last: "34" and "52 ms".
    private func normalEnds(_ kind: TrendKind, _ normal: ClosedRange<Double>) -> (low: String, high: String) {
        let low = kind.format(normal.lowerBound, units: units)
        let high = kind.format(normal.upperBound, units: units)
        guard kind != .sleep, kind != .inBed, let unit = high.split(separator: " ").last, low.hasSuffix(" \(unit)") else { return (low, high) }
        return (String(low.dropLast(unit.count + 1)), high)
    }

    /// The picture of `night` against its normal for a signal page; nil while learning or with no normal.
    func picture(_ kind: TrendKind, night: TrendNight) -> NightPicture? {
        guard let normal = night.normal, night.mark != nil || kind == .inBed else { return nil }
        let mark = night.mark
        let units = units
        let scale = NormalScale.scale(
            value: night.value, low: normal.lowerBound, high: normal.upperBound, floor: kind == .skinTemperature ? nil : 0,
            ceiling: kind == .efficiency ? 100 : nil
        )
        let ends = normalEnds(kind, normal)
        let value = kind.format(night.value, units: units)
        let when = YoursText.night(night.metric.day, today: today, zone: zone)
        let spoken = "\(when) \(value)\(mark.map { ", \($0.words)" } ?? ""). Your normal \(ends.low) to \(ends.high)."
        return NightPicture(scale: scale, mark: mark, value: value, low: ends.low, high: ends.high, spoken: spoken)
    }

    private func hundreds(_ steps: Double) -> Int { Int((steps / 100).rounded()) * 100 }

    /// The meaning sheet's "Yours" line for the latest night of `kind`: its value and, where there is a normal, against it.
    func yours(_ kind: TrendKind) -> String? {
        guard let night = latest(kind) else { return nil }
        let metric = night.metric
        let when = YoursText.night(metric.day, today: today, zone: zone)
        let units = units
        switch kind {
        case .hrv, .restingHeartRate, .breathing, .sleep, .skinTemperature:
            return ContributorReading(metric).map { YoursText.contributor($0, when: when, units: units) }
        case .inBed, .efficiency:
            let value = kind.format(metric.value, units: units)
            guard let normal = normalText(kind) else {
                return "\(when): \(value). \(LearningText.nights(settling(kind)?.earlierNights ?? 0))."
            }
            return "\(when): \(value), \(night.mark.map { "\($0.words) (\(normal))" } ?? "your normal is \(normal)")."
        case .lowestHeartRate:
            let nights = settling(kind)?.earlierNights ?? 0
            let words = YoursText.vsUsual(
                value: metric.value,
                range: night.normal.map { PersonalRange(mean: ($0.lowerBound + $0.upperBound) / 2, sd: ($0.upperBound - $0.lowerBound) / 2, nights: 0) },
                nights: nights, text: { kind.format($0, units: units) }
            )
            return "\(when): \(kind.format(metric.value, units: units)), \(words)."
        case .recovery:
            guard let status = RecoveryStatus(metric) else { return nil }
            return "\(metric.day == today ? "This morning" : "On \(Formatters.day(metric.day, zone: zone))"): \(status.word), \(status.indicator) of 6."
        case .calm:
            let day = YoursText.day(metric.day, today: today, zone: zone)
            let normal = normalText(kind).map { ", your normal is \($0)" } ?? ""
            return "\(day): \(DurationText.hoursMinutes(minutes: metric.value))\(normal)."
        case .steps:
            let day = YoursText.day(metric.day, today: today, zone: zone)
            let normal = normalText(kind).map { ", your normal is \($0)" } ?? ""
            return "\(day): \(kind.format(metric.value, units: units))\(metric.day == today ? " so far" : "")\(normal)."
        }
    }

    /// The header of the period: the plain average of the days with a number ("48 ms", "average a night"); for recovery its most frequent verdict.
    /// Steps leave today out: the day isn't over.
    func periodSummary(_ kind: TrendKind) -> HeaderText? {
        let range = Self.dateRange(firstDay, end, zone: zone)
        let nights = inRange(kind).filter { kind != .steps || $0.metric.day != today }
        guard !nights.isEmpty else { return nil }
        if kind == .recovery {
            let words = nights.compactMap { night in RecoveryStatus(night.metric).map { (day: night.metric.day, value: $0.verdict) } }
            return PeriodWindow.mostFrequent(words).map { HeaderText(label: "Most nights", value: $0, line: range) }
        }
        guard let average = PeriodWindow.average(nights.map(\.value)) else { return nil }
        let unit = kind.isPerDay ? "average a day" : "average a night"
        return HeaderText(label: unit.capitalizedFirst, value: kind.format(average, units: units), line: range)
    }

    /// What the finger on `date` reads: that day's value and its date. Nil when the day has no number.
    func scrubText(_ kind: TrendKind, at date: Date) -> HeaderText? {
        let day = DayKey(date, in: zone)
        guard let night = inRange(kind).first(where: { $0.metric.day == day }) else { return nil }
        let value = kind.text(night.metric, units: units) + (kind == .steps && day == today ? " so far" : "")
        return HeaderText(label: nil, value: value, line: Formatters.day(day, zone: zone))
    }

    /// What VoiceOver reads for the finger on `date`: the touched night's text and, where it has one, the mark's words.
    func scrubSpoken(_ kind: TrendKind, at date: Date) -> String? {
        guard let text = scrubText(kind, at: date) else { return nil }
        let day = DayKey(date, in: zone)
        let words = inRange(kind).first { $0.metric.day == day }?.mark.map { ", \($0.words)" } ?? ""
        return "\(text.line), \(text.value)\(words)"
    }

    static func dateRange(_ first: DayKey, _ last: DayKey, zone: TimeZone) -> String {
        (first.start(in: zone)..<last.start(in: zone)).formatted(Date.IntervalFormatStyle(timeZone: zone).month(.abbreviated).day())
    }

    /// The latest number's own explanation, folded inside the meaning sheet.
    func explanations(_ kind: TrendKind) -> [(label: String, explanation: Explanation)] {
        latest(kind).map { [(kind.title, $0.explanation)] } ?? []
    }

    /// The numbers and their normals; the page that shows only charts stops here.
    func observe() async {
        async let trends: Void = observeTrends()
        async let lines: Void = observeDayLines()
        _ = await (trends, lines)
    }

    func observeFitness() async {
        let today = clock.today
        await reads.observe {
            for try await inputs in database.observeFitnessInputs(today: today) {
                fitness = inputs.map { FitnessAge.estimate($0, today: today) }
                measuredVO2max = inputs?.profile.measuredVO2max
            }
        }
    }

    private func observeTrends() async {
        await reads.observe {
            for try await value in database.observeTrends(endingOn: end, kinds: kinds) {
                series = value.series
                rebuild()
            }
        }
    }

    private func observeDayLines() async {
        await reads.observe {
            for try await value in database.observeDayLines(from: firstDay, through: end) {
                dayLines = value
                rebuild()
            }
        }
    }

    private func rebuild() {
        guard let series, let dayLines else { return }
        var result: [TrendKind: [TrendNight]] = [:]
        for kind in TrendKind.allCases {
            result[kind] = Self.nights(kind, metrics: series[kind.metricKind] ?? [], dayLines: dayLines)
        }
        nights = result
        isReady = true
    }

    /// Each night with its own normal: stored with the night for the contributors, 4 to 6 for recovery, nothing up to that
    /// day's allowance for calm, and worked out here from the 28 nights before it for the lowest heart rate.
    private static func nights(_ kind: TrendKind, metrics: [ComputedMetric], dayLines: [DayKey: DayLines]) -> [TrendNight] {
        let byNight = Dictionary(metrics.map { ($0.day, $0.value) }, uniquingKeysWith: { _, last in last })
        return metrics.compactMap { metric in
            let value: Double
            let normal: ClosedRange<Double>?
            var explanation = metric.explanation
            var mark: NormalMark?
            var normalExplanation: Explanation?
            switch kind {
            case .recovery:
                guard let status = RecoveryStatus(metric) else { return nil }
                value = min(Double(status.indicator) + Double(status.subLevel) / 100, 6)
                normal = Double(InRange.recoveryInside)...6
                mark = status.mark
            case .calm:
                value = metric.value
                normal = dayLines[metric.day]?.calm.normal.high.map { 0...$0 }
            case .steps:
                value = metric.value
                normal = DailySteps.normal(before: metric.day, in: byNight)
            case .lowestHeartRate:
                value = metric.value
                let range = PersonalRange(previous: PersonalRange.previousValues(before: metric.day, in: byNight))
                normal = range.map { $0.low...$0.high }
                mark = range.flatMap { NormalMark(verdict: $0.verdict(of: metric.value), better: .lower) }
                normalExplanation = range?.explanation(unit: "bpm")
            case .inBed:
                value = metric.value
                let range = PersonalRange(previous: PersonalRange.previousValues(before: metric.day, in: byNight))
                normal = range.map { $0.low...$0.high }
                normalExplanation = range?.explanation(unit: "min")
            case .efficiency:
                value = metric.value
                let range = PersonalRange(previous: PersonalRange.previousValues(before: metric.day, in: byNight))
                normal = range?.lowNightsNormal
                mark = range.map { NormalMark(efficiency: metric.value, range: $0) }
                normalExplanation = range?.lowNightsExplanation()
            case .sleep:
                value = metric.value
                let line = InRange.sleep(ContributorReading(metric))
                normal = line.normal.low.flatMap { low in line.normal.high.map { low...$0 } }
                explanation = line.explanation
                mark = ContributorReading(metric)?.mark
            case .hrv, .restingHeartRate, .breathing, .skinTemperature:
                value = metric.value
                let reading = ContributorReading(metric)
                normal = reading?.range.map { $0.low...$0.high }
                mark = reading?.mark
            }
            return TrendNight(metric: metric, value: value, normal: normal, explanation: explanation, mark: mark, normalExplanation: normalExplanation)
        }
    }
}
