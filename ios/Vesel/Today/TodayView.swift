import SwiftUI
import VeselCore
import VeselStorage

struct TodayView: View {
    let environment: AppEnvironment
    let openPage: (PageRoute) -> Void
    let openSyncing: () -> Void
    let readingCard: ReadingCardGate
    @State private var model: TodayModel
    /// Whether last night was already stored when the running read started; nil with no read.
    @State private var nightStoredAtReadStart: Bool?
    /// Bumped by Try again, so the reads start over.
    @State private var attempt = 0
    @State private var showsRestartSteps = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWorkout) private var openWorkout

    init(environment: AppEnvironment, readingCard: ReadingCardGate, openPage: @escaping (PageRoute) -> Void, openSyncing: @escaping () -> Void) {
        self.environment = environment
        self.readingCard = readingCard
        self.openPage = openPage
        self.openSyncing = openSyncing
        let liveHeartRate = environment.liveHeartRate
        let continuedRead = environment.continuedRead
        _model = State(
            initialValue: TodayModel(
                database: environment.database,
                clock: environment.clock,
                status: environment.status,
                units: environment.units,
                defaults: environment.defaults,
                liveReading: { liveHeartRate.reading(at: $0) },
                sync: { await continuedRead.sync($0) },
                failsFirstRead: environment.launch.failsFirstRead
            ))
    }

    private var state: TodayState { model.state(readingCard: readingCard) }

    var body: some View {
        TabScreen(title: "Today", warm: state.somethingOff) {
            content
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: readingCard.isShown && readingProgress != nil)
        .task(id: ObserveKey(value: model.today, active: scenePhase == .active, attempt: attempt)) {
            guard scenePhase == .active else { return }
            await model.observe()
        }
        .task(id: ObserveKey(value: model.today, active: scenePhase == .active, attempt: attempt)) {
            guard scenePhase == .active else { return }
            await model.observeHeartRate()
        }
        .task(id: ObserveKey(value: model.today, active: scenePhase == .active, attempt: attempt)) {
            guard scenePhase == .active else { return }
            await model.observeRuns()
        }
        .sheet(isPresented: $showsRestartSteps) { RestartLoopSheet() }
        .task(id: ObserveKey(value: model.today, active: scenePhase == .active, attempt: attempt)) {
            guard scenePhase == .active else { return }
            await model.observeStepHours()
        }
        .task(id: ObserveKey(value: model.today, active: scenePhase == .active, attempt: attempt)) {
            guard scenePhase == .active else { return }
            await model.observeWorkouts()
        }
        .onChange(of: readKey, initial: true) { _, key in
            if !key.reading {
                nightStoredAtReadStart = nil
            } else if nightStoredAtReadStart == nil, key.loaded {
                nightStoredAtReadStart = model.snapshot?.latest?.night == model.today
            }
        }
    }

    @ViewBuilder private var content: some View {
        Text(Formatters.day(model.today, zone: model.zone))
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Palette.mutedText)
            .padding(.top, -Theme.Spacing.s16)
        if model.readProblem {
            ReadProblemCard { attempt += 1 }
        } else if model.snapshot == nil {
            skeleton
        } else {
            let progress = readingCard.isShown ? readingProgress : nil
            // First: getting up is the one thing on Today that can't wait. Redrawn so the 6-hour and 2-hour windows end on screen.
            if state.morningCard != .none {
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    switch state.morningCard {
                    case .goodMorning:
                        GoodMorningCard(imUp: { Task { await model.imUp() } }, stillInBed: model.stillInBed)
                    case .evaluating(let waitingForLoop):
                        EvaluatingNightCard(
                            waitingForLoop: waitingForLoop, reportOn: model.snapshot?.morningReportOn ?? false,
                            checksUntil: environment.status.nightChecksUntil(at: environment.clock.now), zone: model.zone
                        )
                    case .none:
                        EmptyView()
                    }
                }
            }
            switch state.body {
            case .reading:
                if model.headline != nil || model.snapshot?.latest != nil {
                    summary(progress: progress)
                }
            case .unreachable:
                if model.snapshot?.latest != nil {
                    summary(progress: nil, dimmed: true)
                }
            case .waitingForLoop:
                if model.snapshot?.latest != nil {
                    summary(progress: nil)
                }
            case .noSleep:
                if state.morningCard == .none {
                    if let headline = model.headline {
                        headlineBlock(headline)
                        GlassCard {
                            LineRow(
                                title: "Stress", value: model.calmRingText(at: environment.clock.now), verdict: model.snapshot?.lines.calm,
                                color: Theme.Palette.stress, action: { openPage(PageRoute(kind: .stress, day: model.today)) }, hint: "Opens Stress"
                            )
                        }
                    } else {
                        // While the band still records, the night is coming: "I'm up" above says so.
                        EmptyState(
                            systemImage: "moon",
                            title: "No sleep recorded yet",
                            message: "Wear your Loop tonight; the report appears after you wake up."
                        )
                    }
                }
            case .firstDay, .normal:
                summary(progress: progress)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HeartRateCard(
                    live: model.live(at: context.date), latest: model.snapshot?.latestHeartRate, resting: model.restingHeartRate,
                    points: model.heartRate.loaded(model.today)?.points ?? [], workouts: model.heartRate.workouts(model.today), day: model.today,
                    now: environment.clock.now, zone: model.zone,
                    action: { openPage(PageRoute(kind: .heartRate, day: model.today)) }
                )
            }
            StepsCard(
                steps: model.snapshot?.steps, readAt: model.snapshot?.stepsReadAt, hours: model.stepHours,
                day: model.today, now: environment.clock.now, zone: model.zone,
                action: { openPage(PageRoute(kind: .steps, day: model.today)) }
            )
            WorkoutLines(workouts: model.workouts, zone: model.zone, open: { openWorkout($0) })
            ForEach(model.alerts, id: \.kind) { alert in
                AlertCard(alert: alert) {
                    switch alert.kind {
                    case .longHighStress: openPage(PageRoute(kind: .stress, day: model.today))
                    default: openPage(PageRoute(kind: .recovery, day: model.today))
                    }
                }
            }
            if let since = model.loopStuckSince {
                ErrorCard(
                    title: "Your Loop is stuck",
                    message: "It has said it's busy at every read since \(stuckTime(since)). A restart fixes it and keeps your data.",
                    actionTitle: "How to restart",
                    action: { showsRestartSteps = true }
                )
            }
            // Last, so the reading card appearing and folding away never moves a card above it.
            switch state.body {
            case .reading where model.headline == nil && model.snapshot?.latest == nil:
                if let progress = readingProgress {
                    ReadingList(progress: progress, showsNight: showsNightRow)
                }
            case .unreachable(let lastRead):
                ErrorCard(
                    title: "Can't reach your Loop",
                    message: "Bring it close and try again.",
                    actionTitle: "Try again",
                    action: { Task { await model.tryAgain() } },
                    link: (lastRead.map { "Last read at \(Formatters.time($0, zone: model.zone))" } ?? "Syncing", openSyncing)
                )
            case .waitingForLoop:
                WaitingForLoopCard()
            default:
                if let progress {
                    ReadingList(progress: progress, showsNight: showsNightRow)
                        .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                }
            }
        }
    }

    /// "17:45" today, "Fri 17:45" before.
    private func stuckTime(_ date: Date) -> String {
        DayKey(date, in: model.zone) == model.today
            ? Formatters.time(date, zone: model.zone)
            : date.formatted(Date.FormatStyle(timeZone: model.zone).weekday(.abbreviated).hour().minute())
    }

    /// The reading list's "Last night" row: only while last night isn't on the phone, decided when the read starts so the row
    /// doesn't vanish as the night comes in.
    private var showsNightRow: Bool { nightStoredAtReadStart != true }

    private var readKey: ReadKey { ReadKey(reading: readingProgress != nil, loaded: model.snapshot != nil) }

    private struct ReadKey: Equatable {
        let reading: Bool
        let loaded: Bool
    }

    private var readingProgress: SyncProgress? {
        if case .reading(let progress) = environment.status.sync { progress } else { nil }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s16) {
            SkeletonBlock(height: 32, width: 260)
            SkeletonBlock(height: 18, width: 200)
            VStack(spacing: Theme.Spacing.s16) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
                        SkeletonBlock(height: 16, width: 120)
                        Capsule()
                            .fill(Theme.Palette.mutedText.opacity(0.16))
                            .frame(height: 10)
                    }
                }
            }
            GlassCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                    SkeletonBlock(height: 20, width: 120)
                    SkeletonBlock(height: 40)
                    SkeletonBlock(height: 40)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reading last night")
    }

    private func headlineBlock(_ headline: Headline) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
            Text(headline.sentence)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            if !headline.why.isEmpty {
                Text(headline.why)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The headline and the lines. While a read is going (`progress`) they stay, faded; the reading list sits at the bottom.
    /// An older night never stands in for last night: until last night is in, its headline and lines are left out.
    @ViewBuilder private func summary(progress: SyncProgress?, dimmed: Bool = false) -> some View {
        let snapshot = model.snapshot
        VStack(alignment: .leading, spacing: Theme.Spacing.s24) {
            if state.lastNightMissing {
                if !state.lastNightPending, state.morningCard == .none {
                    Text("Last night isn't in yet. It fills in on the next read.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let headline = model.headline {
                headlineBlock(headline)
                    .opacity(progress != nil ? 0.55 : 1)
            }
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                LineRows(
                    night: state.lastNightMissing ? nil : snapshot?.latest,
                    nightPending: state.lastNightPending,
                    dayLines: snapshot?.lines,
                    firstWeek: snapshot?.firstWeek,
                    zone: model.zone,
                    calmText: model.calmRingText(at: environment.clock.now),
                    openRecovery: { openPage(PageRoute(kind: .recovery, day: model.today)) },
                    openSleep: { openPage(PageRoute(kind: .sleep, day: model.today)) },
                    openCalm: { openPage(PageRoute(kind: .stress, day: model.today)) }
                )
            }
            .opacity(progress != nil ? 0.55 : 1)
        }
        .opacity(dimmed ? 0.55 : 1)
    }
}

#if DEBUG
private struct PreviewToday: View {
    let scenario: PreviewScenario

    var body: some View {
        PreviewHost(scenario) { environment in
            NavigationStack {
                TodayView(environment: environment, readingCard: ReadingCardGate(isReading: false), openPage: { _ in }, openSyncing: {})
                    .toolbarVisibility(.hidden, for: .navigationBar)
            }
        }
    }
}

#Preview("Normal") { PreviewToday(scenario: .normal) }
#Preview("First day") { PreviewToday(scenario: .firstDay) }
#Preview("Read problem") { PreviewToday(scenario: .readProblem) }
#endif
