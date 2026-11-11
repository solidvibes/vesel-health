import SwiftUI
import VeselCore
import VeselStorage

/// One workout, explained: its sport, when, the route on Apple's map, heart rate, load, calories and how it's worked out.
/// Not a signal page: no D · W · M · 3M and no comparison with other workouts. Its heart-rate chart is exempt from the page
/// rule: it is one workout, with no period to step through.
struct WorkoutPage: View {
    @State private var model: WorkoutPageModel
    @State private var showsSports: Bool
    @State private var selection: Date?
    @State private var titleHeight: CGFloat = 0
    @State private var titlePassed = false
    /// Bumped by Try again, so the read starts over.
    @State private var attempt = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.showMeaning) private var showMeaning

    init(route: WorkoutRoute, environment: AppEnvironment) {
        let database = environment.database
        let clock = environment.clock
        _model = State(
            initialValue: WorkoutPageModel(
                database: database, clock: clock, units: environment.units, session: route.session,
                recomputeStress: { days in _ = try? await MetricsUpdater(database: database, clock: clock).recomputeStress(days: days) }
            ))
        _showsSports = State(initialValue: environment.launch.opensWorkoutSport)
    }

    var body: some View {
        ZStack {
            BlobBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.s24) {
                    if model.readProblem {
                        ReadProblemCard { attempt += 1 }
                    } else if let labelled = model.labelled {
                        content(labelled)
                    } else if model.isLoaded {
                        Text("This workout isn't on your phone.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.mutedText)
                    } else {
                        SkeletonBlock(height: 40, width: 200)
                        SkeletonBlock(height: 200)
                    }
                }
                .padding(.horizontal, Theme.Spacing.edge)
                .padding(.top, Theme.Spacing.s16)
                .padding(.bottom, Theme.Spacing.s48)
            }
            .onScrollGeometryChange(for: Bool.self) {
                $0.contentOffset.y + $0.contentInsets.top > Theme.Spacing.s16 + titleHeight
            } action: { _, passed in
                titlePassed = passed
            }
            .scrollEdgeEffectStyle(.hard, for: .top)
            TopFade()
        }
        .navigationBarTitleDisplayMode(.inline)
        .barTitle(model.label?.name ?? "Workout", shown: titlePassed)
        .sheet(isPresented: $showsSports) {
            WorkoutSportSheet(
                sports: model.sheetSports, current: model.label?.source == .owner ? model.label?.sport : nil,
                choose: { sport in Task { await model.choose(sport) } },
                notAWorkout: { Task { await model.notAWorkout() } }
            )
        }
        .onChange(of: model.isClosed) { _, closed in
            if closed { dismiss() }
        }
        .task(id: ObserveKey(value: model.session, active: scenePhase == .active, attempt: attempt)) {
            guard scenePhase == .active else { return }
            await model.observe()
        }
    }

    @ViewBuilder private func content(_ labelled: LabelledWorkout) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
            TermTitle(term: .workout, title: labelled.label.name, font: Theme.Typography.display, isHeader: true)
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: {
                    titleHeight = $0
                }
                .underBar(titlePassed)
            if let chip = model.guessChip {
                Button(chip) { showsSports = true }
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Palette.text)
                    .padding(.horizontal, Theme.Spacing.s12)
                    .frame(minHeight: Theme.Size.tapTarget)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .accessibilityLabel(chip.replacingOccurrences(of: " · change", with: ""))
                    .accessibilityHint("Changes the sport")
            }
            if let line = model.dateLine {
                Text(line)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.mutedText)
            }
        }
        if !model.routePoints.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
                RouteMap(points: model.routePoints, summary: model.routeLine ?? "")
                if let line = model.routeLine {
                    Text(line)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.text)
                }
            }
        }
        heartRate(labelled)
        loadAndCalories(labelled)
        if model.isSwim {
            Text("Heart rate at the wrist is less exact in water.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        Button("Change the sport") { showsSports = true }
            .buttonStyle(.veselSecondary)
        if let explanation = model.explanation {
            HowItsWorkedOutRow(explanations: [explanation])
        }
    }

    @ViewBuilder private func heartRate(_ labelled: LabelledWorkout) -> some View {
        let workout = labelled.workout
        let points = model.heartPoints
        let zone = model.zone
        if !points.isEmpty || workout.averageHeartRate != nil {
            GlassCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                    Text("Heart rate")
                        .font(Theme.Typography.heading)
                        .foregroundStyle(Theme.Palette.text)
                        .accessibilityAddTraits(.isHeader)
                    if !points.isEmpty {
                        let domain = workout.start...max(workout.end, workout.start.addingTimeInterval(60))
                        let text = selection.map { moment -> String in
                            let found = ReadingDayChart.scrubText(at: moment, points: points, zone: zone, unit: "bpm", format: { Formatters.whole($0) })
                            return "\(found.time) · \(found.reading)"
                        }
                        Text(text ?? "Hold, then drag, to read a moment.")
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.Palette.mutedText)
                            .accessibilityHidden(true)
                        ReadingLineChart(
                            points: points, domain: domain, marks: [], zone: zone, color: Theme.Palette.workout,
                            scrub: .holdThenDrag(slot: { Int($0.timeIntervalSince1970) / 60 }), selection: $selection
                        )
                        .scrubAccessibility(
                            $selection, domain: domain, step: 60, label: "Heart rate during the \(labelled.label.noun)", value: text ?? "")
                        HStack {
                            Text(Formatters.clock(workout.start, zone: zone))
                            Spacer(minLength: Theme.Spacing.s8)
                            Text(Formatters.clock(workout.end, zone: zone))
                        }
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Palette.mutedText)
                        .accessibilityHidden(true)
                    }
                    VStack(spacing: 0) {
                        if let average = workout.averageHeartRate { ListRow(label: "Average", value: "\(average) bpm") }
                        if let highest = workout.maxHeartRate { ListRow(label: "Highest", value: "\(highest) bpm") }
                    }
                }
            }
        }
    }

    @ViewBuilder private func loadAndCalories(_ labelled: LabelledWorkout) -> some View {
        let load = model.load
        let calories = labelled.workout.calories
        if load != nil || calories != nil {
            GlassCard {
                VStack(spacing: 0) {
                    if let load {
                        Button {
                            showMeaning(
                                MeaningRequest(
                                    term: .cardioLoad, yours: model.loadYours,
                                    explanations: model.explanation.map { [("Load", $0)] } ?? []))
                        } label: {
                            HStack(spacing: Theme.Spacing.s12) {
                                AdaptiveRow {
                                    Text("Load")
                                        .font(Theme.Typography.body)
                                        .foregroundStyle(Theme.Palette.text)
                                } trailing: {
                                    Text(load.text)
                                        .font(Theme.Typography.body)
                                        .foregroundStyle(Theme.Palette.mutedText)
                                        .multilineTextAlignment(.trailing)
                                }
                                Image(systemName: "chevron.right")
                                    .font(Theme.Typography.small)
                                    .foregroundStyle(Theme.Palette.mutedText)
                                    .accessibilityHidden(true)
                            }
                            .frame(minHeight: Theme.Size.row)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Load")
                        .accessibilityValue(load.spokenText)
                        .accessibilityHint("Shows what it means and where it came from")
                    }
                    if let calories {
                        if load != nil { Divider() }
                        ListRow(label: "Calories", value: "\(calories) kcal")
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview("Ride") {
    PreviewHost { environment in
        NavigationStack {
            WorkoutPage(route: WorkoutRoute(session: "20261024/183000"), environment: environment)
        }
    }
}

#Preview("Run") {
    PreviewHost { environment in
        NavigationStack {
            WorkoutPage(route: WorkoutRoute(session: "20261025/071000"), environment: environment)
        }
    }
}
#endif
