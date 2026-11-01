import Observation
import SwiftUI
import VeselCore
import VeselStorage

/// What the Syncing page knows: the sync log in plain words, and Sync now.
@MainActor
@Observable
final class SyncingModel {
    enum Mark: Equatable {
        case done, problem, running

        var symbol: String {
            switch self {
            case .done: "checkmark.circle"
            case .problem: "exclamationmark.circle"
            case .running: "clock"
            }
        }
    }

    struct Row: Identifiable, Equatable {
        let id: Int64
        let time: String
        let trigger: String
        let outcome: String
        let mark: Mark
    }

    struct Group: Identifiable, Equatable {
        let title: String
        let rows: [Row]
        var id: String { title }
    }

    private(set) var log: SyncLog?
    private(set) var syncing = false
    private(set) var lastOutcome: SyncOutcome?

    private let reads = ReadProblem()
    private let database: AppDatabase
    private let status: SyncStatusStore
    private let clock: any VeselClock
    private let runSync: () async -> SyncOutcome?

    init(database: AppDatabase, status: SyncStatusStore, clock: any VeselClock, runSync: @escaping () async -> SyncOutcome?) {
        self.database = database
        self.status = status
        self.clock = clock
        self.runSync = runSync
    }

    /// A read failed; the page shows its one "Couldn't show this" card.
    var readProblem: Bool { reads.isShown }

    func observe() async {
        await reads.observe {
            for try await value in database.observeSyncRuns(limit: 20) { log = value }
        }
    }

    func syncNow() async {
        syncing = true
        lastOutcome = await runSync()
        syncing = false
    }

    var title: String {
        guard let lastRead = log?.lastRead else { return "Not read yet" }
        return "Last read \(Formatters.ago(lastRead, now: clock.now))"
    }

    /// Only when the newest finished try wasn't a success.
    var trouble: String? {
        guard let log, log.triesSinceLastRead > 0 else { return nil }
        guard let lastRead = log.lastRead else { return "Vesel hasn't read your Loop yet." }
        let tries = log.triesSinceLastRead == 1 ? "1 time" : "\(log.triesSinceLastRead) times"
        return "Vesel hasn't reached your Loop since \(moment(lastRead)). It tried \(tries)."
    }

    var rows: [Row] {
        guard let log else { return [] }
        let zone = clock.timeZone
        return log.runs.enumerated().map { index, run in
            let running = index == 0 && run.outcome == nil && status.sync.isReading
            return Row(
                id: run.id,
                time: Formatters.time(run.startedAt, zone: zone),
                trigger: SyncRunWords.trigger(run.trigger),
                outcome: SyncRunWords.outcome(run, isRunning: running),
                mark: running ? .running : (run.outcome == .success ? .done : .problem)
            )
        }
    }

    var groups: [Group] {
        guard let log else { return [] }
        let zone = clock.timeZone
        let today = clock.today
        let rows = rows
        var result: [Group] = []
        for (run, row) in zip(log.runs, rows) {
            let day = DayKey(run.startedAt, in: zone)
            let title = day == today ? "Today" : day == today.adding(days: -1) ? "Yesterday" : Formatters.day(day, zone: zone)
            if let last = result.last, last.title == title {
                result[result.count - 1] = Group(title: title, rows: last.rows + [row])
            } else {
                result.append(Group(title: title, rows: [row]))
            }
        }
        return result
    }

    private func moment(_ date: Date) -> String {
        let zone = clock.timeZone
        let time = Formatters.time(date, zone: zone)
        let day = DayKey(date, in: zone)
        return day == clock.today ? time : "\(Formatters.day(day, zone: zone)), \(time)"
    }
}

/// Last read, Sync now, what to try when it's stuck, and the recent syncs in words.
struct SyncingView: View {
    @State private var model: SyncingModel
    /// Bumped by Try again, so the read starts over.
    @State private var attempt = 0
    @Environment(\.scenePhase) private var scenePhase

    init(environment: AppEnvironment) {
        let continuedRead = environment.continuedRead
        _model = State(
            initialValue: SyncingModel(
                database: environment.database,
                status: environment.status,
                clock: environment.clock,
                runSync: { await continuedRead.sync(.manual) }
            ))
    }

    private static let steps = [
        "If the Polar Flow app is on this iPhone, close it. It can hold on to the Loop so Vesel can't reach it.",
        "Check Bluetooth is on and the Loop is within a few metres of your iPhone.",
        "Don't swipe Vesel away in the app switcher. That stops background syncs until you open it again.",
        "Tap Sync now and keep Vesel open for about 30 seconds.",
        "Still nothing: turn Bluetooth off and on in Settings, then tap Sync now again.",
    ]

    var body: some View {
        ZStack {
            BlobBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.s24) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
                        Text(model.title)
                            .font(Theme.Typography.title)
                            .foregroundStyle(Theme.Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        if let trouble = model.trouble {
                            Text(trouble)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Palette.mutedText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Button {
                        Task { await model.syncNow() }
                    } label: {
                        if model.syncing { ProgressView() } else { Text("Sync now") }
                    }
                    .buttonStyle(.veselSecondary)
                    .disabled(model.syncing)
                    if !model.syncing, model.lastOutcome == .unreachable || model.lastOutcome == .failed {
                        ErrorCard(
                            title: model.lastOutcome == .unreachable ? "Couldn't reach your Loop" : "The read didn't finish",
                            message: "Keep your Loop close to your iPhone and try again. Nothing was cleared from it."
                        )
                    }
                    stuck
                    if model.readProblem {
                        ReadProblemCard { attempt += 1 }
                    } else {
                        recent
                    }
                }
                .padding(.horizontal, Theme.Spacing.edge)
                .padding(.top, Theme.Spacing.s16)
                .padding(.bottom, Theme.Spacing.s32)
            }
            TopFade()
        }
        .navigationTitle("Syncing")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: ObserveKey(value: scenePhase, active: scenePhase == .active, attempt: attempt)) {
            guard scenePhase == .active else { return }
            await model.observe()
        }
    }

    private var stuck: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
            Text("If it's stuck")
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Palette.mutedText)
                .accessibilityAddTraits(.isHeader)
            GlassCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                    ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s12) {
                            Text("\(index + 1).")
                                .font(Theme.Typography.body.monospacedDigit())
                                .foregroundStyle(Theme.Palette.mutedText)
                                .accessibilityHidden(true)
                            Text(step)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Step \(index + 1). \(step)")
                    }
                    Divider()
                    Text(
                        "Nothing is lost for now: your Loop keeps its readings until Vesel has stored them, as long as its storage doesn't fill up. Band storage in Loop & settings shows how full it is."
                    )
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder private var recent: some View {
        if !model.groups.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
                Text("Recent syncs")
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .accessibilityAddTraits(.isHeader)
                ForEach(model.groups) { group in
                    VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
                        Text(group.title)
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.Palette.mutedText)
                        GlassCard {
                            VStack(spacing: 0) {
                                ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                                    if index > 0 { Divider() }
                                    SyncRowView(row: row)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct SyncRowView: View {
    let row: SyncingModel.Row

    var body: some View {
        AdaptiveRow {
            Text("\(row.time) · \(row.trigger)")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.text)
        } trailing: {
            HStack(spacing: Theme.Spacing.s8) {
                Text(row.outcome)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .multilineTextAlignment(.trailing)
                Image(systemName: row.mark.symbol)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: Theme.Size.row)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.time), \(row.trigger), \(row.outcome)")
    }
}

#if DEBUG
#Preview("Normal") {
    PreviewHost { environment in
        NavigationStack { SyncingView(environment: environment) }
    }
}
#endif
