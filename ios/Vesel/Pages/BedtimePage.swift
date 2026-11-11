import Charts
import SwiftUI
import VeselCore
import VeselStorage

/// The bedtimes and wake times of the nights a window covers, read only where the Bedtime page and Sleep's W, M and 3M rows show them.
@MainActor
@Observable
final class BedtimeModel {
    let period: PagePeriod
    let end: DayKey
    private(set) var nights: [SleepNightTimes]?
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
    var today: DayKey { clock.today }
    var firstDay: DayKey { PeriodWindow.first(endingOn: end, period: period) }
    var domain: ClosedRange<Date> { firstDay.start(in: zone)...end.adding(days: 1).start(in: zone) }
    var ticks: [TrendTick] { BodyModel.ticks(period: period, end: end, zone: zone) }
    var isReady: Bool { nights != nil }
    /// A read failed; the page shows its one "Couldn't show this" card.
    var readProblem: Bool { reads.isShown }
    var range: String { BodyModel.dateRange(firstDay, end, zone: zone) }

    /// The middle bedtime and wake time of the nights shown.
    var times: SleepTimes? { nights.flatMap { SleepTimes.make(nights: $0, zone: zone) } }

    func night(_ day: DayKey) -> SleepNightTimes? { nights?.first { $0.night == day } }

    /// "23:20 to 07:08", on a 24-hour clock whatever the phone's own setting is.
    func text(_ night: SleepNightTimes) -> String { "\(Formatters.clock(night.start, zone: zone)) to \(Formatters.clock(night.end, zone: zone))" }

    /// A bedtime before 18:00 sits at the top of the axis; its text still says the real time.
    func bedMinutes(_ night: SleepNightTimes) -> Int {
        let minutes = ClockMedian.minutesAfter18(of: night.start, zone: zone)
        return minutes >= Self.dayMinutes ? 0 : minutes
    }

    func wakeMinutes(_ night: SleepNightTimes) -> Int { ClockMedian.minutesAfter18(of: night.end, zone: zone) }

    /// The axis runs from 18:00 to 12:00, or to the next whole hour after the latest wake when that is later.
    var axisMinutes: Int {
        let latest = (nights ?? []).map(wakeMinutes).max() ?? 0
        return max(Self.dayMinutes, (latest + 59) / 60 * 60)
    }

    private static let dayMinutes = 18 * 60

    /// "18:00" for the minutes after 18:00 on the axis.
    static func axisLabel(minutes: Int) -> String {
        let clock = (minutes + dayMinutes) % (24 * 60)
        return String(format: "%02d:00", clock / 60)
    }

    /// What the finger on `date` reads: that night's times and its date. Nil on a day with no night.
    func scrubText(at date: Date) -> HeaderText? {
        let day = DayKey(date, in: zone)
        guard let found = night(day) else { return nil }
        return HeaderText(label: nil, value: text(found), line: Formatters.day(day, zone: zone))
    }

    /// "Monday 2 November, 23:20 to 07:08"
    func spoken(at date: Date) -> String? {
        let day = DayKey(date, in: zone)
        guard let found = night(day) else { return nil }
        let long = day.start(in: zone).formatted(Date.FormatStyle(timeZone: zone).weekday(.wide).day().month(.wide))
        return "\(long), \(text(found))"
    }

    func observe() async {
        await reads.observe {
            for try await value in database.observeSleepTimes(endingOn: end, days: period.days) { nights = value }
        }
    }
}

/// One floating bar a night from bedtime to wake, on a clock axis with evening at the top so a later night sits lower. There is no
/// band and no mark: two clock times a night crossing midnight have no normal to sit in. The Bedtime page's chart.
private struct BedtimeChart: View {
    let model: BedtimeModel
    var highlighted: DayKey?
    @Binding var selection: Date?
    @Environment(SignalPageModel.self) private var page
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let zone = model.zone
        let nights = model.nights ?? []
        let axis = model.axisMinutes
        let selected = selection.flatMap { model.night(DayKey($0, in: zone)) }
        Chart {
            ForEach(nights, id: \.night) { night in
                BarMark(
                    x: .value("Night", night.night.start(in: zone), unit: .day), yStart: .value("Bedtime", -Double(model.bedMinutes(night))),
                    yEnd: .value("Wake", -Double(model.wakeMinutes(night)))
                )
                .foregroundStyle(Theme.Palette.sleep.opacity(highlighted == nil || night.night == highlighted ? 1 : 0.35))
                .cornerRadius(3)
            }
            if let selected { ScrubRule(date: BodyModel.midday(selected.night, zone: zone)) }
        }
        .chartXScale(domain: model.domain)
        .chartYScale(domain: -Double(axis)...0)
        .trendAxes(
            ticks: model.ticks, yValues: stride(from: 0, through: axis, by: 180).map { -Double($0) },
            yLabel: { BedtimeModel.axisLabel(minutes: Int(-$0)) }, showsNumbers: !typeSize.isAccessibilitySize
        )
        .frame(height: 240)
        .chartScrub(
            $selection,
            style: .holdThenDrag(slot: { SignalChart.slot(of: $0, zone: zone) }, onTap: { page.pick(DayKey($0, in: zone)) })
        )
    }
}

private struct BedtimeChartCard: View {
    let model: BedtimeModel
    var highlighted: DayKey?
    @Binding var selection: Date?
    @Environment(SignalPageModel.self) private var page

    var body: some View {
        GlassCard {
            if !model.isReady {
                SkeletonBlock(height: 240)
            } else if (model.nights ?? []).isEmpty {
                Text("No sleep recorded in this range yet.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.mutedText)
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                    BedtimeChart(model: model, highlighted: highlighted, selection: $selection)
                        .scrubAccessibility(
                            $selection, domain: model.domain, step: 86_400, label: "Bedtime and wake, \(model.range)",
                            value: selection.flatMap { model.spoken(at: $0) } ?? ""
                        )
                        .accessibilityActions {
                            if let selection {
                                Button("Show this night") { page.pick(DayKey(selection, in: model.zone)) }
                            }
                        }
                    Text("Each bar runs from the night's bedtime down to its wake time; the hours on the side are the clock.")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Palette.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Bedtime and wake for one night, in the 7 nights it sits in, that night drawn in full and the others faded.
struct BedtimeDayPart: View {
    let day: DayKey
    @State private var model: BedtimeModel
    @State private var selection: Date?
    @Environment(\.setPageMeaning) private var setMeaning
    @Environment(\.scenePhase) private var scenePhase

    init(environment: AppEnvironment, day: DayKey) {
        self.day = day
        _model = State(initialValue: BedtimeModel(database: environment.database, clock: environment.clock, period: .week, end: day))
    }

    private var header: HeaderText {
        let line = PageDayLine.night(day, shown: day, today: model.today, zone: model.zone)
        guard model.isReady else { return HeaderText(value: "—", line: line) }
        return HeaderText(value: model.night(day).map(model.text) ?? "No sleep recorded", line: line)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s24) {
            PageHeader(text: header, scrub: selection.flatMap { model.scrubText(at: $0) })
            BedtimeChartCard(model: model, highlighted: day, selection: $selection)
        }
        .readProblem(model.readProblem)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.observe()
        }
        .onChange(of: model.isReady, initial: true) {
            setMeaning(
                PageMeaning(
                    yours: model.night(day).map { "\(YoursText.night(day, today: model.today, zone: model.zone)): \(model.text($0))." }, explanations: []
                ))
        }
    }
}

/// Bedtime and wake over W, M and 3M: the middle bedtime and wake time over a bar for each night; a tap on a night opens it.
struct BedtimePeriodPart: View {
    @State private var model: BedtimeModel
    @State private var selection: Date?
    @Environment(\.setPageMeaning) private var setMeaning
    @Environment(\.scenePhase) private var scenePhase

    init(environment: AppEnvironment, period: PagePeriod, end: DayKey) {
        _model = State(initialValue: BedtimeModel(database: environment.database, clock: environment.clock, period: period, end: end))
    }

    private var header: HeaderText {
        guard let times = model.times else { return HeaderText(value: model.isReady ? "No sleep recorded" : "—", line: model.range) }
        return HeaderText(label: "Usually", value: times.text, line: model.range)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s24) {
            PageHeader(text: header, scrub: selection.flatMap { model.scrubText(at: $0) })
            BedtimeChartCard(model: model, selection: $selection)
            if let times = model.times {
                HowItsWorkedOutRow(explanations: [times.explanation])
            }
        }
        .readProblem(model.readProblem)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.observe()
        }
        .onChange(of: model.times, initial: true) {
            setMeaning(PageMeaning(yours: nil, explanations: model.times.map { [("Bedtime and wake", $0.explanation)] } ?? []))
        }
    }
}

#if DEBUG
#Preview("Day") { PreviewPage(kind: .bedtime) }
#Preview("4 weeks") { PreviewPage(kind: .bedtime, period: .month) }
#Preview("In bed") { PreviewPage(kind: .inBed) }
#Preview("Efficiency 4 weeks") { PreviewPage(kind: .efficiency, period: .month) }
#endif
