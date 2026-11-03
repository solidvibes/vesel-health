import SwiftUI
import VeselCore
import VeselStorage

/// Journal: what happened on the picked day. Its night (sleep, recovery), its workouts, and its day (calm, heart rate, steps), each at a
/// glance and a link to its page.
struct JournalView: View {
    let environment: AppEnvironment
    @State private var model: JournalModel
    @State private var showsCalendar: Bool
    /// Bumped by Try again, so the reads start over.
    @State private var attempt = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openPage) private var openPage
    @Environment(\.openWorkout) private var openWorkout

    init(environment: AppEnvironment) {
        self.environment = environment
        _model = State(
            initialValue: JournalModel(
                database: environment.database,
                clock: environment.clock,
                status: environment.status,
                units: environment.units,
                days: environment.days
            ))
        _showsCalendar = State(initialValue: environment.launch.opensCalendar)
    }

    var body: some View {
        TabScreen(
            title: Formatters.day(model.day, zone: model.zone),
            onTitleTap: { showsCalendar = true },
            accessory: {
                if !model.isToday { BackToTodayPill(environment: environment) }
            }
        ) {
            if environment.days.firstDay != nil {
                WeekStrip(environment: environment)
            }
            if model.readProblem {
                ReadProblemCard { attempt += 1 }
            } else {
                night
                if !model.workouts.isEmpty { workouts }
                day
            }
        }
        .sheet(isPresented: $showsCalendar) {
            DayCalendar(environment: environment)
        }
        .task(id: ObserveKey(value: model.day, active: scenePhase == .active, attempt: attempt)) {
            guard scenePhase == .active else { return }
            await model.observe()
        }
        .task(id: ObserveKey(value: model.day, active: scenePhase == .active, attempt: attempt)) {
            guard scenePhase == .active else { return }
            await model.observeHeartRate()
        }
        .task(id: ObserveKey(value: model.day, active: scenePhase == .active, attempt: attempt)) {
            guard scenePhase == .active else { return }
            await model.observeStress()
        }
        .task(id: ObserveKey(value: model.day, active: scenePhase == .active, attempt: attempt)) {
            guard scenePhase == .active else { return }
            await model.observeSteps()
        }
        .task(id: ObserveKey(value: model.day, active: scenePhase == .active, attempt: attempt)) {
            guard scenePhase == .active else { return }
            await model.observeWorkouts()
        }
    }

    /// Only on a day with a workout, between the night and the day.
    private var workouts: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
            JournalHeading(title: "Workouts", line: nil)
            ForEach(model.workouts, id: \.workout.session) { labelled in
                WorkoutCard(labelled: labelled, zone: model.zone) {
                    openWorkout(WorkoutRoute(session: labelled.workout.session))
                }
            }
        }
    }

    private var night: some View {
        let lines = model.snapshot?.lines ?? .empty
        let report = model.night
        let zone = model.zone
        return VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
            JournalHeading(title: "Night", line: model.nightLine)
            JournalCard(
                title: "Sleep", value: model.sleepValue, state: report == nil ? .none : lines.sleep.state,
                color: Theme.Palette.sleep,
                summary: report?.sleep.map { "asleep \(Formatters.clock($0.start, zone: zone)) to \(Formatters.clock($0.end, zone: zone))" },
                hint: "Opens Sleep"
            ) {
                openPage(PageRoute(kind: .sleep, day: model.day))
            } glance: {
                if let sleep = report?.sleep {
                    SleepStagesChart(night: sleep, marks: [], selection: .constant(nil), compact: true)
                    GlanceEnds(leading: Formatters.clock(sleep.start, zone: zone), trailing: Formatters.clock(sleep.end, zone: zone))
                }
            }
            let main = model.mainContributor
            JournalCard(
                title: "Recovery", value: model.recoveryValue, state: report?.status == nil ? .none : lines.recovery.state,
                color: Theme.Palette.recoveryLine(report?.status), summary: main.map { contributorText($0).joined(separator: ", ") },
                hint: "Opens Recovery"
            ) {
                openPage(PageRoute(kind: .recovery, day: model.day))
            } glance: {
                if report?.status != nil {
                    RangeLine(
                        scale: lines.recovery.scale, outside: lines.recovery.state.isOutside, color: Theme.Palette.recoveryLine(report?.status), height: 8)
                    if let main {
                        let text = contributorText(main)
                        GlanceEnds(leading: text[0], trailing: text.count > 1 ? text[1] : "")
                    }
                }
            }
        }
    }

    /// "HRV 46 ms" and "usual".
    private func contributorText(_ reading: ContributorReading) -> [String] {
        let name = reading.contributor == .hrv ? "HRV" : reading.contributor.title
        return ["\(name) \(reading.valueText(units: model.units))", reading.verdictWord].compactMap { $0 }
    }

    private var day: some View {
        let lines = model.snapshot?.lines ?? .empty
        let hours = model.stressHours
        let zone = model.zone
        return VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
            JournalHeading(title: "Day", line: nil)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let value =
                    hours.isEmpty && lines.highMinutes == nil
                    ? (model.isToday ? "No stress readings yet" : "No stress readings")
                    : model.calmValue(at: context.date)
                JournalCard(
                    title: "Stress", value: value, state: lines.calm.state, color: Theme.Palette.stress,
                    summary: StressModel.peak(hours), hint: "Opens Stress"
                ) {
                    openPage(PageRoute(kind: .stress, day: model.day))
                } glance: {
                    if !hours.isEmpty {
                        HourlyStressChart(
                            hours: hours, day: model.day, zone: zone, workouts: model.heartRate.workouts(model.day), compact: true, selection: .constant(nil))
                    }
                }
            }
            let range = model.heartRateRange
            let points = model.heartRate.loaded(model.day)?.points ?? []
            JournalCard(
                title: "Heart rate",
                value: range.map { "\(Formatters.whole($0.lowest))–\(Formatters.whole($0.highest)) bpm" }
                    ?? (model.heartRateIsReady ? "No heart rate recorded" : "—"),
                state: .none, color: Theme.Palette.recovery,
                summary: range.map {
                    "lowest \(Formatters.whole($0.lowest)) at \(Formatters.clock($0.lowestAt, zone: zone)), highest \(Formatters.whole($0.highest)) at \(Formatters.clock($0.highestAt, zone: zone))"
                },
                hint: "Opens Heart rate"
            ) {
                openPage(PageRoute(kind: .heartRate, day: model.day))
            } glance: {
                if !points.isEmpty {
                    let start = model.day.start(in: zone)
                    ReadingLineChart(
                        points: points, domain: start...model.day.adding(days: 1).start(in: zone), marks: [], zone: zone,
                        color: Theme.Palette.recovery, workouts: model.heartRate.workouts(model.day), yDomain: HeartRateCard.fitted(points), height: 44,
                        selection: .constant(nil)
                    )
                    GlanceEnds(leading: "00:00", trailing: "24:00")
                }
            }
            if let steps = model.snapshot?.steps {
                let hours = model.stepHours
                JournalCard(
                    title: "Steps", value: model.isToday ? "\(Formatters.steps(steps)) so far" : Formatters.steps(steps),
                    state: .none, color: Theme.Palette.mutedText, hint: "Opens Steps"
                ) {
                    openPage(PageRoute(kind: .steps, day: model.day))
                } glance: {
                    if !hours.isEmpty {
                        HourlyStepsGlance(hours: hours, day: model.day, zone: zone)
                        GlanceEnds(leading: "00:00", trailing: "24:00")
                    }
                }
            }
        }
    }
}

/// The two ends under a glance chart: bedtime and wake time, the hours of the day.
private struct GlanceEnds: View {
    let leading: String
    let trailing: String

    var body: some View {
        HStack {
            Text(leading)
            Spacer(minLength: Theme.Spacing.s8)
            Text(trailing)
        }
        .font(Theme.Typography.small)
        .foregroundStyle(Theme.Palette.mutedText)
    }
}

private struct JournalHeading: View {
    let title: String
    let line: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
            Text(title)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.text)
                .accessibilityAddTraits(.isHeader)
            if let line {
                Text(line)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.mutedText)
            }
        }
    }
}

/// One link to a page: its name, its value, where it sits against your normal (a dot and its word, never colour alone), a chevron,
/// and under them the day at a glance. VoiceOver reads it all as one: the value, then `summary`.
struct JournalCard<Glance: View>: View {
    let title: String
    let value: String
    let state: LineState
    let color: Color
    var summary: String?
    let hint: String
    let action: () -> Void
    @ViewBuilder let glance: () -> Glance

    var body: some View {
        Button(action: action) {
            GlassCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
                    HStack(spacing: Theme.Spacing.s12) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
                            Text(title)
                                .font(Theme.Typography.label)
                                .foregroundStyle(Theme.Palette.mutedText)
                            Text(value)
                                .font(Theme.Typography.heading)
                                .foregroundStyle(Theme.Palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                            if state != .none {
                                HStack(spacing: Theme.Spacing.s8) {
                                    DotMark(state: DotState(state), color: color)
                                        .accessibilityHidden(true)
                                    Text(state.rowWord)
                                        .font(Theme.Typography.small)
                                        .foregroundStyle(Theme.Palette.mutedText)
                                }
                            }
                        }
                        Spacer(minLength: Theme.Spacing.s8)
                        Image(systemName: "chevron.right")
                            .font(Theme.Typography.label)
                            .foregroundStyle(Theme.Palette.mutedText)
                            .accessibilityHidden(true)
                    }
                    glance()
                        .allowsHitTesting(false)
                }
                .frame(minHeight: Theme.Size.tapTarget)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue([state.spokenValue(value), summary].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(hint)
    }
}

#if DEBUG
#Preview("Normal") {
    PreviewHost { environment in
        NavigationStack {
            JournalView(environment: environment)
                .toolbarVisibility(.hidden, for: .navigationBar)
        }
    }
}

#Preview("First day") {
    PreviewHost(.firstDay) { environment in
        NavigationStack {
            JournalView(environment: environment)
                .toolbarVisibility(.hidden, for: .navigationBar)
        }
    }
}
#endif
