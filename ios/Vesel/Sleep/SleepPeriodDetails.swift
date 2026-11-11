import Charts
import SwiftUI
import VeselCore
import VeselStorage

/// The deep, light and REM minutes of the nights a window covers, read only where the Stages card shows them.
@MainActor
@Observable
final class SleepStagesModel {
    private(set) var nights: [NightStages]?
    private let reads = ReadProblem()
    private let database: AppDatabase
    private let period: PagePeriod
    private let end: DayKey

    init(database: AppDatabase, period: PagePeriod, end: DayKey) {
        self.database = database
        self.period = period
        self.end = end
    }

    /// A read failed; the page shows its one "Couldn't show this" card.
    var readProblem: Bool { reads.isShown }

    /// What the finger on `date` reads: that night's stages and its date. Nil on a night with none.
    func scrubText(at date: Date, zone: TimeZone) -> HeaderText? {
        let day = DayKey(date, in: zone)
        guard let found = nights?.first(where: { $0.night == day }) else { return nil }
        let text = [("Deep", found.deep), ("Light", found.light), ("REM", found.rem)]
            .map { "\($0.0) \(DurationText.hoursMinutes(minutes: $0.1))" }.joined(separator: " · ")
        return HeaderText(label: nil, value: text, line: Formatters.day(day, zone: zone))
    }

    func observe() async {
        await reads.observe {
            for try await value in database.observeSleepStages(endingOn: end, days: period.days) { nights = value }
        }
    }
}

/// Under Sleep's time-asleep bars on W, M and 3M: a Stages card with one stacked bar per night and its legend, then In bed, Efficiency and
/// Bedtime · wake, each a row that opens its page on the same window. Its chart's finger reads into the page's header.
struct SleepPeriodDetails: View {
    let trends: BodyModel
    @Binding var selection: Date?
    @Binding var reading: HeaderText?
    @State private var stages: SleepStagesModel
    @State private var bedtimes: BedtimeModel
    @Environment(SignalPageModel.self) private var page
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize

    init(environment: AppEnvironment, trends: BodyModel, selection: Binding<Date?>, reading: Binding<HeaderText?>) {
        self.trends = trends
        _selection = selection
        _reading = reading
        _stages = State(initialValue: SleepStagesModel(database: environment.database, period: trends.period, end: trends.end))
        _bedtimes = State(
            initialValue: BedtimeModel(database: environment.database, clock: environment.clock, period: trends.period, end: trends.end))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s24) {
            stagesCard
            rowsCard
        }
        .readProblem(stages.readProblem || bedtimes.readProblem)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await stages.observe()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await bedtimes.observe()
        }
        .onChange(of: selection) {
            reading = selection.flatMap { stages.scrubText(at: $0, zone: trends.zone) }
        }
    }

    private var stagesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                Text("Stages")
                    .font(Theme.Typography.heading)
                    .foregroundStyle(Theme.Palette.text)
                    .accessibilityAddTraits(.isHeader)
                if let nights = stages.nights, !nights.isEmpty {
                    chart(nights)
                        .scrubAccessibility(
                            $selection, domain: trends.domain, step: 86_400, label: "Stages, \(trends.period.unit)",
                            value: selection.flatMap { stages.scrubText(at: $0, zone: trends.zone) }.map { "\($0.line), \($0.value)" } ?? ""
                        )
                        .accessibilityActions {
                            if let selection {
                                Button("Show this night") { page.pick(DayKey(selection, in: trends.zone)) }
                            }
                        }
                    legend
                    Text("Deep, light and REM sleep each night; awake time is left out. Hold a finger on a night, then drag, to read it.")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Palette.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                } else if stages.nights == nil {
                    SkeletonBlock(height: 180)
                } else {
                    Text("No stages recorded in this range yet.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.mutedText)
                }
            }
        }
    }

    private func chart(_ nights: [NightStages]) -> some View {
        let zone = trends.zone
        let tallest = nights.map { ($0.deep + $0.light + $0.rem) / 60 }.max() ?? 1
        let selected = selection.flatMap { moment in nights.first { $0.night == DayKey(moment, in: zone) } }
        return Chart {
            ForEach(nights, id: \.night) { night in
                let day = night.night.start(in: zone)
                let deep = night.deep / 60
                let light = deep + night.light / 60
                BarMark(x: .value("Day", day, unit: .day), yStart: .value("From", 0.0), yEnd: .value("Deep", deep))
                    .foregroundStyle(SleepStagesChart.color(.deep))
                BarMark(x: .value("Day", day, unit: .day), yStart: .value("From", deep), yEnd: .value("Light", light))
                    .foregroundStyle(SleepStagesChart.color(.light))
                BarMark(x: .value("Day", day, unit: .day), yStart: .value("From", light), yEnd: .value("REM", light + night.rem / 60))
                    .foregroundStyle(SleepStagesChart.color(.rem))
            }
            if let selected { ScrubRule(date: BodyModel.midday(selected.night, zone: zone)) }
        }
        .chartXScale(domain: trends.domain)
        .chartYScale(domain: 0...max(tallest * 1.15, 1))
        .trendAxes(ticks: trends.ticks, yValues: nil, showsNumbers: !typeSize.isAccessibilitySize)
        .chartYAxisLabel(position: .trailing) { Text("hours") }
        .frame(height: 180)
        .chartScrub(
            $selection,
            style: .holdThenDrag(slot: { SignalChart.slot(of: $0, zone: zone) }, onTap: { page.pick(DayKey($0, in: zone)) })
        )
    }

    private var legend: some View {
        let layout =
            typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.s8)) : AnyLayout(HStackLayout(spacing: Theme.Spacing.s16))
        return layout {
            ForEach([SleepState.deep, .light, .rem], id: \.self) { state in
                HStack(spacing: Theme.Spacing.s8) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(SleepStagesChart.color(state))
                        .frame(width: 12, height: 12)
                    Text(SleepStagesChart.label(state))
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Palette.mutedText)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bottom to top: Deep, Light, REM")
    }

    private var rowsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
                Text("Across these nights")
                    .font(Theme.Typography.heading)
                    .foregroundStyle(Theme.Palette.text)
                    .accessibilityAddTraits(.isHeader)
                SignalLinkRow(kind: .inBed, value: trends.periodSummary(.inBed)?.value ?? "—", day: trends.end, period: trends.period)
                Divider()
                SignalLinkRow(kind: .efficiency, value: trends.periodSummary(.efficiency)?.value ?? "—", day: trends.end, period: trends.period)
                Divider()
                SignalLinkRow(kind: .bedtime, value: bedtimes.times?.text ?? "—", day: trends.end, period: trends.period)
            }
        }
    }
}
