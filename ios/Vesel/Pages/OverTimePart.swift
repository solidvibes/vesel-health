import SwiftUI
import VeselCore

/// W, M and 3M for one signal: the average, the chart over your moving normal, and how the latest number is worked out. A page can
/// fill `slot` between the chart and the worked-out card (only Sleep does) with a second chart; the header reads whichever chart a finger
/// is on, and starting on one clears the other. The slot gets the page's model and its chart's selection and header reading to set.
struct OverTimePart<Slot: View>: View {
    let kind: TrendKind
    @State private var model: BodyModel
    @State private var selection: Date?
    @State private var slotSelection: Date?
    @State private var slotReading: HeaderText?
    private let slot: (BodyModel, Binding<Date?>, Binding<HeaderText?>) -> Slot
    @Environment(SignalPageModel.self) private var page
    @Environment(\.setPageMeaning) private var setMeaning
    @Environment(\.scenePhase) private var scenePhase

    init(
        environment: AppEnvironment, kind: TrendKind, period: PagePeriod, end: DayKey, kinds: [String]? = nil,
        @ViewBuilder slot: @escaping (BodyModel, Binding<Date?>, Binding<HeaderText?>) -> Slot
    ) {
        self.kind = kind
        self.slot = slot
        _model = State(
            initialValue: BodyModel(
                database: environment.database, clock: environment.clock, units: environment.units, period: period, endingOn: end,
                kinds: kinds ?? kind.readKinds))
    }

    private var range: String { BodyModel.dateRange(model.firstDay, model.end, zone: model.zone) }

    var body: some View {
        let points = model.points(kind)
        let scrub = selection.flatMap { model.scrubText(kind, at: $0) } ?? (slotSelection == nil ? nil : slotReading)
        VStack(alignment: .leading, spacing: Theme.Spacing.s24) {
            PageHeader(text: model.periodSummary(kind) ?? HeaderText(value: model.isReady ? "No readings" : "—", line: range), scrub: scrub)
            GlassCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                    if !model.isReady {
                        SkeletonBlock(height: 240)
                    } else if points.isEmpty {
                        Text("No readings in this range yet.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.mutedText)
                    } else {
                        SignalChart(
                            kind: kind, points: points, domain: model.domain, ticks: model.ticks, units: model.units,
                            settlingMedian: model.settling(kind)?.median, zone: model.zone, compact: false, selection: $selection,
                            onPickDay: { page.pick($0) }
                        )
                        .scrubAccessibility(
                            $selection, domain: model.domain, step: 86_400, label: "\(kind.title), \(range)",
                            value: selection.flatMap { model.scrubSpoken(kind, at: $0) } ?? ""
                        )
                        .accessibilityActions {
                            if let selection {
                                Button("Show this day") { page.pick(DayKey(selection, in: model.zone)) }
                            }
                        }
                        caption
                    }
                }
            }
            if model.isReady, !points.isEmpty { slot(model, $slotSelection, $slotReading) }
            if let latest = model.latest(kind) {
                GlassCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
                        Text(explanationTitle(latest.metric))
                            .font(Theme.Typography.heading)
                            .foregroundStyle(Theme.Palette.text)
                        ExplanationView(explanation: latest.explanation)
                    }
                }
            }
        }
        .readProblem(model.readProblem)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.observe()
        }
        .onChange(of: selection) {
            if selection != nil { slotSelection = nil }
        }
        .onChange(of: slotSelection) {
            if slotSelection != nil { selection = nil }
        }
        .onChange(of: model.isReady, initial: true) {
            setMeaning(PageMeaning(yours: model.yours(kind), explanations: model.explanations(kind)))
        }
    }

    private func explanationTitle(_ latest: ComputedMetric) -> String {
        guard latest.day != model.end else { return "How it's worked out" }
        return "How it's worked out · \(Formatters.shortDay(latest.day, zone: model.zone))"
    }

    @ViewBuilder private var caption: some View {
        if let learning = model.learningNote(kind) {
            Text(TermLink.text(learning, linking: "usual range", to: .usualRange))
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Palette.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
                Text(kind.shadedNote)
                if kind == .calm { Text("Days with no bar had no stress numbers.") }
                if kind == .steps { Text("Days with no bar had no steps counted.") }
                if kind == .steps, model.latest(kind)?.metric.day == model.today { Text("Today's bar is lighter: the day isn't over.") }
            }
            .font(Theme.Typography.small)
            .foregroundStyle(Theme.Palette.mutedText)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension OverTimePart where Slot == EmptyView {
    init(environment: AppEnvironment, kind: TrendKind, period: PagePeriod, end: DayKey) {
        self.init(environment: environment, kind: kind, period: period, end: end) { _, _, _ in EmptyView() }
    }
}

extension TrendKind {
    /// What the shading behind the chart is.
    var shadedNote: String {
        switch self {
        case .recovery: "Shaded: Polar's OK or better."
        case .calm, .steps: "Shaded: your normal, from the 4 weeks before each day."
        default: "Shaded: your normal, from the 4 weeks before each night."
        }
    }
}
