import SwiftUI
import VeselCore

/// The 7 nights ending on `day`, that night drawn in full and the others faded, over your moving normal. A finger on it replaces the
/// page's header (`BodyModel.scrubText`); a tap on a night opens it. `model` is the owner's, a week ending on `day`.
struct NightsChart: View {
    let kind: TrendKind
    let day: DayKey
    let model: BodyModel
    @Binding var selection: Date?
    @Environment(SignalPageModel.self) private var page

    var body: some View {
        let points = model.points(kind)
        if model.isReady, !points.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                    SignalChart(
                        kind: kind, points: points, domain: model.domain, ticks: model.ticks, units: model.units,
                        settlingMedian: model.settling(kind)?.median, zone: model.zone, compact: false, selection: $selection,
                        highlighted: day, onPickDay: { page.pick($0) }
                    )
                    .scrubAccessibility(
                        $selection, domain: model.domain, step: 86_400, label: "\(kind.title), the 7 nights to \(Formatters.shortDay(day, zone: model.zone))",
                        value: selection.flatMap { model.scrubSpoken(kind, at: $0) } ?? ""
                    )
                    .accessibilityActions {
                        if let selection {
                            Button("Show this night") { page.pick(DayKey(selection, in: model.zone)) }
                        }
                    }
                    caption
                }
            }
        } else if !model.isReady {
            SkeletonBlock(height: 240)
        }
    }

    @ViewBuilder private var caption: some View {
        if let learning = model.learningNote(kind) {
            Text(TermLink.text(learning, linking: "usual range", to: .usualRange))
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Palette.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(kind.shadedNote)
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Palette.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// D for the overnight measures: the night's number, where it sits against your normal, the week's nights, and how it is worked out.
struct NightlyDayPart: View {
    let kind: TrendKind
    let day: DayKey
    @State private var model: BodyModel
    @State private var selection: Date?
    @Environment(\.scenePhase) private var scenePhase

    init(environment: AppEnvironment, kind: TrendKind, day: DayKey) {
        self.kind = kind
        self.day = day
        _model = State(
            initialValue: BodyModel(
                database: environment.database, clock: environment.clock, units: environment.units, period: .week, endingOn: day, kinds: kind.readKinds))
    }

    private var night: TrendNight? { model.inRange(kind).first { $0.metric.day == day } }

    @ViewBuilder private func workedOut(_ night: TrendNight) -> some View {
        let numbers = [night.explanation] + [night.normalExplanation].compactMap { $0 }
        let labels = numbers.count > 1 ? [kind.title, "Your normal"] : []
        if let normal = model.normalText(kind) {
            GlassCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
                    Text("How it's worked out")
                        .font(Theme.Typography.heading)
                        .foregroundStyle(Theme.Palette.text)
                    Text(kind.normalSentence(normal))
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if let goodOrBad = Glossary.goodOrBad(kind.term) {
                        Text(goodOrBad)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HowItsWorkedOutRow(framed: false, title: "Show the numbers", explanations: numbers, labels: labels)
                }
            }
        } else {
            HowItsWorkedOutRow(title: "Show the numbers", explanations: numbers, labels: labels)
        }
    }

    var body: some View {
        let line = PageDayLine.night(day, shown: day, today: model.today, zone: model.zone)
        let scrub = selection.flatMap { model.scrubText(kind, at: $0) }
        VStack(alignment: .leading, spacing: Theme.Spacing.s24) {
            if !model.isReady {
                PageHeader(text: HeaderText(value: "—", line: line))
                SkeletonBlock(height: 240)
            } else if let night {
                PageHeader(text: HeaderText(value: kind.text(night.metric, units: model.units), line: line), scrub: scrub)
                if let picture = model.picture(kind, night: night) {
                    GlassCard {
                        NormalPicture(
                            scale: picture.scale, mark: picture.mark, color: kind.color, value: picture.value, low: picture.low, high: picture.high,
                            spoken: picture.spoken
                        )
                    }
                }
                NightsChart(kind: kind, day: day, model: model, selection: $selection)
                workedOut(night)
            } else {
                PageHeader(text: HeaderText(value: "No reading", line: line), scrub: scrub)
                NightsChart(kind: kind, day: day, model: model, selection: $selection)
                Text("Your Loop has no \(kind.title.lowercased()) stored for this night.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.mutedText)
            }
        }
        .readProblem(model.readProblem)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.observe()
        }
    }
}

extension TrendKind {
    /// The "How it's worked out" line for the normal: efficiency's has more room below the mean than above it.
    func normalSentence(_ normal: String) -> String {
        self == .efficiency
            ? "Your normal comes from your last 4 weeks of nights, with more room below the middle than above: \(normal)."
            : "Your normal is the middle of your last 4 weeks of nights: \(normal)."
    }
}
