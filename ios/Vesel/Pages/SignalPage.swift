import Observation
import SwiftUI
import VeselCore
import VeselStorage

/// Everything that has a page: one chart with a Day, Week, 4 weeks and 3 months view.
enum PageKind: String, Hashable {
    case recovery, sleep, stress, heartRate, steps, hrv, restingHeartRate, lowestHeartRate, breathing, skinTemperature, inBed, efficiency, bedtime

    init(_ trend: TrendKind) {
        switch trend {
        case .recovery: self = .recovery
        case .sleep: self = .sleep
        case .calm: self = .stress
        case .steps: self = .steps
        case .hrv: self = .hrv
        case .restingHeartRate: self = .restingHeartRate
        case .lowestHeartRate: self = .lowestHeartRate
        case .breathing: self = .breathing
        case .skinTemperature: self = .skinTemperature
        case .inBed: self = .inBed
        case .efficiency: self = .efficiency
        }
    }

    /// Nil for heart rate and bedtime, which have no number a night to put on a band; their W, M and 3M are `HeartRateDaysPart` and `BedtimePeriodPart`.
    var trend: TrendKind? {
        switch self {
        case .recovery: .recovery
        case .sleep: .sleep
        case .stress: .calm
        case .steps: .steps
        case .hrv: .hrv
        case .restingHeartRate: .restingHeartRate
        case .lowestHeartRate: .lowestHeartRate
        case .breathing: .breathing
        case .skinTemperature: .skinTemperature
        case .inBed: .inBed
        case .efficiency: .efficiency
        case .heartRate, .bedtime: nil
        }
    }

    var title: String { trend?.title ?? (self == .bedtime ? "Bedtime · wake" : "Heart rate") }
    var term: Term { trend?.term ?? (self == .bedtime ? .bedtime : .heartRate) }
}

extension PagePeriod {
    var shortLabel: String {
        switch self {
        case .day: "D"
        case .week: "W"
        case .month: "M"
        case .quarter: "3M"
        }
    }

    var spoken: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "4 weeks"
        case .quarter: "3 months"
        }
    }

    /// What ‹ and › move by.
    var unit: String {
        switch self {
        case .day: "day"
        case .week: "week"
        case .month: "4 weeks"
        case .quarter: "3 months"
        }
    }

    /// `-VeselPeriod d|w|m|3m`.
    init?(launch name: String) {
        switch name {
        case "d": self = .day
        case "w": self = .week
        case "m": self = .month
        case "3m": self = .quarter
        default: return nil
        }
    }
}

/// What the header over a chart says: an optional small label, the big value and the date or dates under it.
struct HeaderText: Equatable {
    var label: String?
    let value: String
    let line: String
}

/// What the title's meaning sheet says about a page's number; each built part fills in its own page's.
struct PageMeaning {
    var yours: String?
    var explanations: [(label: String, explanation: Explanation)] = []
}

/// Gives the title's meaning sheet what a part says about its own page: `@Environment(\.setPageMeaning) var setMeaning`.
struct SetPageMeaning {
    let action: @MainActor (PageMeaning) -> Void

    @MainActor func callAsFunction(_ meaning: PageMeaning) { action(meaning) }
}

extension EnvironmentValues {
    @Entry var setPageMeaning = SetPageMeaning(action: { _ in })
    @Entry var showReadProblem = ShowReadProblem(action: {})
    /// The period page a part sits on, so its ‹ › show that page's ends, not the shown page's, mid-swipe.
    @Entry var periodPage: SignalPageModel.PageID?
}

/// Tells the period page that a part couldn't read its data; the page shows its one card in the part's place.
struct ShowReadProblem {
    let action: @MainActor () -> Void

    @MainActor func callAsFunction() { action() }
}

extension View {
    /// A part of a period page hands a failed read to the page.
    func readProblem(_ isShown: Bool) -> some View {
        modifier(ReportReadProblem(isShown: isShown))
    }
}

private struct ReportReadProblem: ViewModifier {
    let isShown: Bool
    @Environment(\.showReadProblem) private var show

    func body(content: Content) -> some View {
        content.onChange(of: isShown, initial: true) {
            if isShown { show() }
        }
    }
}

/// Where a page is: its view (period), the day D shows and the day the W, M and 3M window ends on.
@MainActor
@Observable
final class SignalPageModel {
    struct Position: Hashable {
        let period: PagePeriod
        let day: DayKey
        let end: DayKey
    }

    /// One page of the row a sideways drag moves through: its view and the day it shows (D) or ends on (W, M, 3M).
    struct PageID: Hashable {
        let period: PagePeriod
        let day: DayKey
    }

    let kind: PageKind
    private(set) var period: PagePeriod
    private(set) var day: DayKey
    private(set) var end: DayKey
    /// What each built page's part says; the title shows the shown page's.
    var meanings: [PageID: PageMeaning] = [:]
    /// Whether the big title has scrolled under the top bar.
    var titlePassed = false
    /// The day the page was opened on; the row reaches back to it even before the first day with data.
    private let opened: DayKey
    private let clock: any VeselClock
    private let days: DaySelection

    init(route: PageRoute, clock: any VeselClock, days: DaySelection) {
        self.clock = clock
        self.days = days
        kind = route.kind
        let today = clock.today
        let period = route.period
        let day = min(route.day, today)
        self.period = period
        self.day = day
        opened = day
        end = PeriodWindow.end(holding: day, period: period, today: today)
    }

    var today: DayKey { clock.today }
    var position: Position { Position(period: period, day: day, end: end) }

    private var focus: DayKey { period == .day ? day : end }

    var current: PageID { PageID(period: period, day: focus) }
    var meaning: PageMeaning? { meanings[current] }

    /// The first day with data, from Journal's one read of it, bounds the row (or the opened day, if earlier); unknown keeps only the
    /// shown page.
    var pages: [PageID] {
        PeriodWindow.pages(period: period, holding: focus, firstDay: days.firstDay.map { min($0, opened) }, today: today).map {
            PageID(period: period, day: $0)
        }
    }

    func canPageLater(from page: PageID) -> Bool { PeriodWindow.canPageLater(end: page.day, today: today) }
    func canPageEarlier(from page: PageID) -> Bool { pages.first.map { $0 != page } ?? false }

    func select(_ new: PagePeriod) {
        guard new != period else { return }
        if new != .day { end = PeriodWindow.end(holding: focus, period: new, today: today) }
        period = new
        meanings = [:]
    }

    /// The page the row settled on.
    func show(_ page: PageID) {
        guard page.period == period, page != current else { return }
        if period == .day { day = page.day } else { end = page.day }
    }

    /// One period earlier (−1) or later (+1).
    func page(_ steps: Int) {
        guard steps < 0 ? canPageEarlier(from: current) : canPageLater(from: current) else { return }
        let target = PeriodWindow.paged(end: focus, by: steps, period: period, today: today)
        if period == .day { day = target } else { end = target }
    }

    /// A day tapped in W, M or 3M: its D.
    func pick(_ picked: DayKey) {
        guard period != .day || min(picked, today) != day else { return }
        day = min(picked, today)
        period = .day
        meanings = [:]
    }
}

/// One page for one thing: the title and the D · W · M · 3M switch stay put over a row of period pages, one per period from the first
/// day with data to today, that a sideways drag anywhere moves through. Each period page has the header and chart for its view, and the
/// day's cards on D. One vertical scroll holds both, so the title scrolls away with whichever page is shown.
struct SignalPage: View {
    @State private var model: SignalPageModel
    @State private var titleHeight: CGFloat = 0
    @State private var pageHeights: [SignalPageModel.PageID: CGFloat] = [:]
    private let environment: AppEnvironment

    init(route: PageRoute, environment: AppEnvironment) {
        self.environment = environment
        _model = State(initialValue: SignalPageModel(route: route, clock: environment.clock, days: environment.days))
    }

    var body: some View {
        ZStack {
            BlobBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.s24) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s24) {
                        TermTitle(
                            term: model.kind.term, title: model.kind.title, font: Theme.Typography.display, isHeader: true,
                            yours: model.meaning?.yours, explanations: model.meaning?.explanations ?? []
                        )
                        .onGeometryChange(for: CGFloat.self) {
                            $0.size.height
                        } action: {
                            titleHeight = $0
                        }
                        .underBar(model.titlePassed)
                        picker
                    }
                    .padding(.horizontal, Theme.Spacing.edge)
                    pager
                }
                .padding(.top, Theme.Spacing.s16)
                .padding(.bottom, Theme.Spacing.s48)
            }
            .onScrollGeometryChange(for: Bool.self) {
                $0.contentOffset.y + $0.contentInsets.top > Theme.Spacing.s16 + titleHeight
            } action: { _, passed in
                model.titlePassed = passed
            }
            .scrollEdgeEffectStyle(.hard, for: .top)
            TopFade()
        }
        .navigationBarTitleDisplayMode(.inline)
        .barTitle(model.kind.title, shown: model.titlePassed)
        .environment(model)
        .sensoryFeedback(.selection, trigger: model.position)
    }

    private var picker: some View {
        Picker("View", selection: Binding(get: { model.period }, set: { model.select($0) })) {
            ForEach(PagePeriod.allCases, id: \.self) { period in
                Text(period.shortLabel).accessibilityLabel(period.spoken).tag(period)
            }
        }
        .pickerStyle(.segmented)
    }

    /// The row is as tall as the tallest built page: a lazy row doesn't grow with its pages by itself, so each page reports its height.
    private var pager: some View {
        let pages = model.pages
        let at = pages.firstIndex(of: model.current) ?? pages.count - 1
        let built = pages.indices.filter { abs($0 - at) <= 1 }.map { pages[$0] }
        return ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 0) {
                ForEach(Array(pages.enumerated()), id: \.element) { index, id in
                    PeriodPage(id: id, isCurrent: index == at, isBuilt: abs(index - at) <= 1, environment: environment)
                        .onGeometryChange(for: CGFloat.self) {
                            $0.size.height
                        } action: {
                            pageHeights[id] = $0
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .frame(height: built.compactMap { pageHeights[$0] }.max())
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: Binding(get: { model.current }, set: { $0.map(model.show) }))
        .defaultScrollAnchor(.trailing)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .id(model.period)
    }
}

/// One period of a signal's page. The shown page and the one on each side of it build their part, so the neighbour under the finger
/// shows real data; pages further away draw a skeleton, so a long row stays light. VoiceOver reads only the shown page.
private struct PeriodPage: View {
    let id: SignalPageModel.PageID
    let isCurrent: Bool
    let isBuilt: Bool
    let environment: AppEnvironment
    @Environment(SignalPageModel.self) private var model
    /// A part couldn't read its data. Try again builds the part afresh, so its reads start over.
    @State private var readProblem = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s24) {
            if isBuilt && readProblem {
                ReadProblemCard { readProblem = false }
            } else if isBuilt {
                part
                    .environment(\.setPageMeaning, SetPageMeaning { [model, id] in model.meanings[id] = $0 })
                    .environment(\.periodPage, id)
                    .environment(\.showReadProblem, ShowReadProblem { readProblem = true })
            } else {
                SkeletonBlock(height: 72)
                SkeletonBlock(height: 240)
            }
        }
        .padding(.horizontal, Theme.Spacing.edge)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityHidden(!isCurrent)
    }

    @ViewBuilder private var part: some View {
        if id.period == .day {
            dayPart
        } else if model.kind == .sleep {
            OverTimePart(
                environment: environment, kind: .sleep, period: id.period, end: id.day,
                kinds: TrendsSnapshot.kinds + [MetricKind.sleepInBed, MetricKind.sleepEfficiency]
            ) { trends, selection, reading in
                SleepPeriodDetails(environment: environment, trends: trends, selection: selection, reading: reading)
            }
        } else if let trend = model.kind.trend {
            OverTimePart(environment: environment, kind: trend, period: id.period, end: id.day)
        } else if model.kind == .bedtime {
            BedtimePeriodPart(environment: environment, period: id.period, end: id.day)
        } else {
            HeartRateDaysPart(environment: environment, period: id.period, end: id.day)
        }
    }

    @ViewBuilder private var dayPart: some View {
        switch model.kind {
        case .recovery: RecoveryDay(environment: environment, day: id.day)
        case .sleep: SleepDay(environment: environment, day: id.day)
        case .stress: CalmDay(environment: environment, day: id.day)
        case .heartRate: HeartRateDay(environment: environment, day: id.day)
        case .steps: StepsDay(environment: environment, day: id.day)
        case .bedtime: BedtimeDayPart(environment: environment, day: id.day)
        case .hrv, .restingHeartRate, .lowestHeartRate, .breathing, .skinTemperature, .inBed, .efficiency:
            if let trend = model.kind.trend { NightlyDayPart(environment: environment, kind: trend, day: id.day) }
        }
    }
}

/// The value over a chart, with the date under it and ‹ › to move one period. A finger on the chart replaces it with the touched
/// point's value and date; lifting it restores it.
struct PageHeader: View {
    let text: HeaderText
    var scrub: HeaderText?
    @Environment(SignalPageModel.self) private var page
    @Environment(\.periodPage) private var periodPage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shown = scrub ?? text
        let own = periodPage ?? page.current
        HStack(spacing: Theme.Spacing.s8) {
            arrow("chevron.left", label: "Earlier \(page.period.unit)", enabled: page.canPageEarlier(from: own)) { move(-1) }
            VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
                if let label = shown.label ?? text.label.map({ _ in " " }) {
                    Text(label)
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Palette.mutedText)
                }
                Text(shown.value)
                    .font(Theme.Typography.title.monospacedDigit())
                    .foregroundStyle(Theme.Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(shown.line)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            arrow("chevron.right", label: "Later \(page.period.unit)", enabled: page.canPageLater(from: own)) { move(1) }
        }
    }

    private func move(_ steps: Int) {
        withAnimation(reduceMotion ? nil : .default) { page.page(steps) }
    }

    private func arrow(_ systemImage: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(Theme.Typography.label)
                .foregroundStyle(enabled ? Theme.Palette.text : Theme.Palette.mutedText.opacity(0.4))
                .frame(minWidth: Theme.Size.tapTarget, minHeight: Theme.Size.tapTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}
