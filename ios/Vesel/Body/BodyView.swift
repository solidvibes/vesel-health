import SwiftUI
import VeselCore

/// How am I changing: every signal over 4 weeks with your normal as a band, each opening its page; then Heart fitness and About you.
struct BodyView: View {
    @State private var model: BodyModel
    @State private var aboutYou: AboutYouModel
    private let environment: AppEnvironment
    @State private var showsFitness = false
    @State private var opensFitnessWhenRead: Bool
    /// Bumped by Try again, so the reads start over.
    @State private var attempt = 0
    @Environment(\.scenePhase) private var scenePhase

    init(environment: AppEnvironment) {
        self.environment = environment
        _opensFitnessWhenRead = State(initialValue: environment.launch.opensFitness)
        _model = State(initialValue: BodyModel(database: environment.database, clock: environment.clock, units: environment.units, period: .month))
        let pipeline = environment.pipeline
        _aboutYou = State(
            initialValue: AboutYouModel(
                database: environment.database,
                clock: environment.clock,
                units: environment.units,
                opensEditor: environment.launch.opensAboutYou,
                writeProfile: { await pipeline.writeProfile($0) }
            ))
    }

    var body: some View {
        TabScreen(title: "Body") {
            if model.readProblem {
                ReadProblemCard { attempt += 1 }
            } else if !model.isReady {
                SkeletonBlock(height: 40)
                SkeletonBlock(height: 280)
            } else if model.hasNothing {
                EmptyState(
                    systemImage: "chart.line.uptrend.xyaxis",
                    title: "No data yet",
                    message: "Body starts after your first night with the Loop."
                )
            } else {
                ForEach(BodyGroup.allCases, id: \.self) { group in
                    VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
                            Text(group.title)
                                .font(Theme.Typography.title)
                                .foregroundStyle(Theme.Palette.text)
                                .accessibilityAddTraits(.isHeader)
                            Text(group.line)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Palette.mutedText)
                        }
                        ForEach(group.kinds, id: \.self) { kind in card(kind) }
                    }
                }
            }
            if let fitness = model.fitness {
                FitnessCard(outcome: fitness, today: model.today, zone: model.zone) { body in
                    Button {
                        showsFitness = true
                    } label: {
                        body
                    }
                    .buttonStyle(.plain)
                }
            }
            if let profile = aboutYou.profile {
                VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
                        Text("About you")
                            .font(Theme.Typography.title)
                            .foregroundStyle(Theme.Palette.text)
                            .accessibilityAddTraits(.isHeader)
                        Text("What Vesel knows about you, and how numbers are written.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.mutedText)
                    }
                    GlassCard {
                        VStack(spacing: 0) { AboutYouSection(model: aboutYou, profile: profile) }
                    }
                }
            }
        }
        .navigationDestination(isPresented: $showsFitness) {
            if let fitness = model.fitness {
                FitnessView(outcome: fitness, measuredVO2max: model.measuredVO2max, today: model.today, zone: model.zone, units: model.units)
            }
        }
        .navigationDestination(isPresented: Binding(get: { aboutYou.editingProfile && aboutYou.profile != nil }, set: { aboutYou.editingProfile = $0 })) {
            if let profile = aboutYou.profile {
                AboutYouEditView(model: aboutYou, stored: profile)
            }
        }
        .onChange(of: model.fitness) {
            guard opensFitnessWhenRead, model.fitness != nil else { return }
            opensFitnessWhenRead = false
            showsFitness = true
        }
        .task(id: ObserveKey(value: scenePhase, active: scenePhase == .active, attempt: attempt)) {
            guard scenePhase == .active else { return }
            await aboutYou.load()
            async let signals: Void = model.observe()
            async let fitness: Void = model.observeFitness()
            _ = await (signals, fitness)
        }
    }

    /// The title opens its meaning; the body opens the signal's page on 4 weeks ending today.
    @ViewBuilder private func card(_ kind: TrendKind) -> some View {
        let latest = model.latest(kind)
        let text = latest.map { kind.text($0.metric, units: model.units) }
        let spoken = [kind.title, text ?? "no readings in this range", model.normalText(kind).map { "your normal now \($0)" }, "opens \(kind.title)"]
            .compactMap { $0 }.joined(separator: ", ")
        let route = PageRoute(kind: PageKind(kind), day: model.today, period: .month)
        BodyCard(
            latest: text,
            chart: SignalChart(
                kind: kind, points: model.points(kind), domain: model.domain, ticks: model.ticks, units: model.units,
                settlingMedian: model.settling(kind)?.median, zone: model.zone
            ),
            note: model.learningNote(kind) ?? model.stepsNote(kind),
            spoken: spoken,
            title: TermTitle(term: kind.term, title: kind.title, yours: model.yours(kind), explanations: model.explanations(kind))
        ) { body in
            NavigationLink(value: route) { body }
        }
    }
}

#if DEBUG
#Preview("Normal") {
    PreviewHost { environment in
        NavigationStack {
            BodyView(environment: environment)
                .toolbarVisibility(.hidden, for: .navigationBar)
        }
    }
}

#Preview("First day") {
    PreviewHost(.firstDay) { environment in
        NavigationStack {
            BodyView(environment: environment)
                .toolbarVisibility(.hidden, for: .navigationBar)
        }
    }
}
#endif
