import Charts
import SwiftUI
import VeselCore
import VeselStorage

/// One day of heart rate for the W, M and 3M chart: the lowest and highest 5-minute average and the average of them all.
struct HeartRateDayRange: Identifiable, Equatable {
    let day: DayKey
    let lowest: Double
    let highest: Double
    let average: Double
    let metric: ComputedMetric
    var id: DayKey { day }
}

/// The heart rate of the days a window covers, grouped on read from the 5-minute averages; nothing is stored. A window is re-read
/// whenever a sample is written while the page is open.
@MainActor
@Observable
final class HeartRateDaysModel {
    let period: PagePeriod
    let end: DayKey
    private(set) var days: [HeartRateDayRange]?
    private let reads = ReadProblem()
    private let database: AppDatabase
    private let clock: any VeselClock

    init(database: AppDatabase, clock: any VeselClock, period: PagePeriod, end: DayKey) {
        self.database = database
        self.clock = clock
        self.period = period
        self.end = end
    }

    var zone: TimeZone { clock.timeZone }
    var firstDay: DayKey { PeriodWindow.first(endingOn: end, period: period) }
    var domain: ClosedRange<Date> { firstDay.start(in: zone)...end.adding(days: 1).start(in: zone) }
    var ticks: [TrendTick] { BodyModel.ticks(period: period, end: end, zone: zone) }
    var isReady: Bool { days != nil }
    /// A read failed; the page shows its one "Couldn't show this" card.
    var readProblem: Bool { reads.isShown }

    /// The lowest to the highest over every shown day, with the dates.
    var summary: HeaderText? {
        guard let days, let low = days.map(\.lowest).min(), let high = days.map(\.highest).max() else { return nil }
        return HeaderText(label: nil, value: "\(Formatters.whole(low))–\(Formatters.whole(high)) bpm", line: BodyModel.dateRange(firstDay, end, zone: zone))
    }

    /// What the finger on `date` reads: that day's range and average. Nil on a day with no readings.
    func scrubText(at date: Date) -> HeaderText? {
        let day = DayKey(date, in: zone)
        guard let found = days?.first(where: { $0.day == day }) else { return nil }
        return HeaderText(
            label: nil, value: "\(Formatters.whole(found.lowest))–\(Formatters.whole(found.highest)) bpm",
            line: "\(Formatters.day(day, zone: zone)) · average \(Formatters.whole(found.average)) bpm"
        )
    }

    func observe() async {
        await reads.observe {
            for try await value in database.observeHeartRatePeriods(endingOn: end, days: period.days, zone: zone) {
                days = await Self.group(value, end: end, zone: zone)
            }
        }
    }

    /// Off the main thread, like every series worked out on read.
    @concurrent nonisolated private static func group(_ periods: [FiveMinuteMean], end: DayKey, zone: TimeZone) async -> [HeartRateDayRange] {
        DailyHeartRate.days(periods: periods, zone: zone, computedAt: end.adding(days: 1).start(in: zone)).compactMap { metric in
            DailyHeartRate.Range(metric).map {
                HeartRateDayRange(day: metric.day, lowest: $0.lowest, highest: $0.highest, average: metric.value, metric: metric)
            }
        }
    }
}

/// Heart rate over W, M and 3M: a bar from each day's lowest to its highest with a dot at its average. There is no normal behind it:
/// heart rate has no daily normal. A finger on it (after a short hold) replaces the header, a swipe pages and a tap opens the day.
struct HeartRateDaysPart: View {
    @State private var model: HeartRateDaysModel
    @State private var selection: Date?
    @Environment(SignalPageModel.self) private var page
    @Environment(\.setPageMeaning) private var setMeaning
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize

    init(environment: AppEnvironment, period: PagePeriod, end: DayKey) {
        _model = State(initialValue: HeartRateDaysModel(database: environment.database, clock: environment.clock, period: period, end: end))
    }

    private var range: String { BodyModel.dateRange(model.firstDay, model.end, zone: model.zone) }

    var body: some View {
        let days = model.days ?? []
        let scrub = selection.flatMap { model.scrubText(at: $0) }
        VStack(alignment: .leading, spacing: Theme.Spacing.s24) {
            PageHeader(text: model.summary ?? HeaderText(value: model.isReady ? "No readings" : "—", line: range), scrub: scrub)
            GlassCard {
                if !model.isReady {
                    SkeletonBlock(height: 240)
                } else if days.isEmpty {
                    Text("No heart rate recorded in this range yet.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.mutedText)
                } else {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                        chart(days)
                            .scrubAccessibility(
                                $selection, domain: model.domain, step: 86_400, label: "Heart rate, \(range)",
                                value: scrub.map { "\($0.line), \($0.value)" } ?? ""
                            )
                            .accessibilityActions {
                                if let selection {
                                    Button("Show this day") { page.pick(DayKey(selection, in: model.zone)) }
                                }
                            }
                        Text("Each bar runs from the day's lowest to its highest 5-minute average; the dot is its average.")
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.Palette.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let latest = days.last {
                HowItsWorkedOutRow(
                    title: latest.day == model.end ? "How it's worked out" : "How it's worked out · \(Formatters.shortDay(latest.day, zone: model.zone))",
                    explanations: [latest.metric.explanation]
                )
            }
        }
        .readProblem(model.readProblem)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.observe()
        }
        .onChange(of: model.isReady, initial: true) {
            setMeaning(
                PageMeaning(
                    yours: nil,
                    explanations: model.days?.last.map { [("Heart rate", $0.metric.explanation)] } ?? []
                ))
        }
    }

    private func chart(_ days: [HeartRateDayRange]) -> some View {
        let zone = model.zone
        let low = days.map(\.lowest).min() ?? 0
        let high = days.map(\.highest).max() ?? 1
        let pad = Swift.max((high - low) * 0.15, 0.5)
        let selected = selection.flatMap { moment in days.first { $0.day == DayKey(moment, in: zone) } }
        let color = Theme.Palette.recovery
        return Chart {
            ForEach(days) { day in
                BarMark(x: .value("Day", day.day.start(in: zone), unit: .day), yStart: .value("Lowest", day.lowest), yEnd: .value("Highest", day.highest))
                    .foregroundStyle(color)
                    .cornerRadius(2)
                PointMark(x: .value("Day", BodyModel.midday(day.day, zone: zone)), y: .value("Average", day.average))
                    .foregroundStyle(Theme.Palette.background)
                    .symbolSize(model.period == .quarter ? 8 : 24)
            }
            if let selected { ScrubRule(date: BodyModel.midday(selected.day, zone: zone)) }
        }
        .chartXScale(domain: model.domain)
        .chartYScale(domain: (low - pad)...(high + pad))
        .trendAxes(ticks: model.ticks, yValues: nil, showsNumbers: !typeSize.isAccessibilitySize)
        .chartYAxisLabel(position: .trailing) { Text("bpm") }
        .frame(height: 240)
        .chartScrub(
            $selection,
            style: .holdThenDrag(slot: { SignalChart.slot(of: $0, zone: zone) }, onTap: { page.pick(DayKey($0, in: zone)) })
        )
    }
}
