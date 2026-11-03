#if DEBUG
import SwiftUI
import VeselCore
import VeselStorage
import VeselWearable
import VeselWearableTesting

/// What a screen preview shows. All of them run on the fake band's made-up data, not real readings.
enum PreviewScenario: CaseIterable {
    /// A paired Loop with 30 days; now is 25 Oct 2026.
    case normal
    /// Only the first four nights: Vesel is still learning your normal.
    case firstDay
    /// No Loop paired yet.
    case unpaired
    /// Like `normal`, but Today's first read fails once.
    case readProblem

    fileprivate var band: FakeScenario {
        switch self {
        case .normal, .readProblem: .normal
        case .firstDay: .firstDay
        case .unpaired: .pairing
        }
    }

    fileprivate var now: Date {
        let day = self == .firstDay ? "2026-09-29" : "2026-10-25"
        return (try? Date("\(day)T15:00:00Z", strategy: .iso8601)) ?? Date(timeIntervalSince1970: 0)
    }
}

/// The environment behind every screen preview: an in-memory database filled once with the fake band's records, a fixed clock and no sync
/// pipeline run, so a preview sends no notification, reloads no widget and backs up nothing.
@MainActor
enum PreviewEnvironment {
    private static var loading: [PreviewScenario: Task<AppEnvironment?, Never>] = [:]

    /// Nil when the fake band's data couldn't be loaded.
    static func environment(_ scenario: PreviewScenario) async -> AppEnvironment? {
        if let task = loading[scenario] { return await task.value }
        let task = Task { await load(scenario) }
        loading[scenario] = task
        return await task.value
    }

    private static func load(_ scenario: PreviewScenario) async -> AppEnvironment? {
        do {
            let band = try FakeWearableSource(scenario: scenario.band)
            let database = try AppDatabase.inMemory()
            let clock = FixedClock(now: scenario.now, timeZone: FakeWearableSource.fixtureZone)
            if scenario != .unpaired { try await fill(database, from: band, clock: clock) }
            let defaults = UserDefaults(suiteName: "app.vesel.preview") ?? .standard
            defaults.removePersistentDomain(forName: "app.vesel.preview")
            var launch = LaunchOptions(defaults: defaults)
            launch.failsFirstRead = scenario == .readProblem
            return AppEnvironment(database: database, band: band, clock: clock, launch: launch, defaults: defaults)
        } catch {
            return nil
        }
    }

    /// The same storage calls `BandSync` makes after a read, then the analysis `SyncPipeline` runs after it.
    private static func fill(_ database: AppDatabase, from band: FakeWearableSource, clock: FixedClock) async throws {
        let pairedAt = Date(timeIntervalSince1970: 1_790_409_600)
        var info = BandInfo(deviceId: "FAKE0001", name: "Polar Loop", pairedAt: pairedAt)
        info.batteryPercent = await band.battery()
        info.batteryAt = clock.now
        let disk = await band.diskSpace()
        info.diskFreeBytes = disk.freeBytes
        info.diskTotalBytes = disk.totalBytes
        info.lastSeenAt = clock.now
        try await database.save(info)
        try await database.save(Profile(birthYear: 1990, sex: .male, heightCm: 180, weightKg: 75, sleepGoalMinutes: 480))
        let first = DayKey(pairedAt, in: clock.timeZone).adding(days: -1)
        var held: [BandPayload] = []
        for kind in FetchKind.allCases {
            let payloads = try await band.fetch(kind, from: first, through: clock.today) {}
            if kind == .heartRate || kind == .ppi {
                try await database.saveReadings(payloads)
                held += payloads
            } else {
                try await database.save(payloads.filter { !$0.isEmpty }, fetchedAt: clock.now)
            }
        }
        for (_, payloads) in Dictionary(grouping: held, by: \.day).sorted(by: { $0.key < $1.key }) {
            try await database.save(payloads, fetchedAt: clock.now)
        }
        for reference in await band.workoutReferences() {
            try await database.save(try await band.workout(reference), storedAt: clock.now)
        }
        let run = try await database.startSyncRun(.manual, at: clock.now)
        try await database.finishSyncRun(run, outcome: .success, detail: nil, at: clock.now)
        try await MetricsUpdater(database: database, clock: clock).updateAfterSync()
    }
}

/// Waits for the preview environment, then shows `content` with it. Wrap a screen that sits in a stack in `NavigationStack` yourself.
struct PreviewHost<Content: View>: View {
    let scenario: PreviewScenario
    @ViewBuilder let content: (AppEnvironment) -> Content
    @State private var environment: AppEnvironment?
    @State private var failed = false

    init(_ scenario: PreviewScenario = .normal, @ViewBuilder content: @escaping (AppEnvironment) -> Content) {
        self.scenario = scenario
        self.content = content
    }

    var body: some View {
        Group {
            if let environment {
                content(environment)
            } else if failed {
                Text("The preview data didn't load.")
            } else {
                ProgressView()
            }
        }
        .task {
            environment = await PreviewEnvironment.environment(scenario)
            failed = environment == nil
        }
    }
}

/// A signal's page on its own stack, opened on the preview's today.
struct PreviewPage: View {
    let kind: PageKind
    var period: PagePeriod = .day
    var scenario: PreviewScenario = .normal

    var body: some View {
        PreviewHost(scenario) { environment in
            NavigationStack {
                SignalPage(route: PageRoute(kind: kind, day: environment.clock.today, period: period), environment: environment)
                    .toolbarVisibility(.hidden, for: .navigationBar)
            }
        }
    }
}

/// A pairing screen on its own model, not searching: `looking` picks what the search found.
struct PreviewPairing<Content: View>: View {
    @State private var model: PairingModel
    @ViewBuilder let content: (PairingModel) -> Content

    init(environment: AppEnvironment, looking: PairingModel.Looking = .searching, @ViewBuilder content: @escaping (PairingModel) -> Content) {
        let model = PairingModel(
            bandSync: environment.bandSync,
            database: environment.database,
            clock: environment.clock,
            units: environment.units,
            launchStep: .before,
            didPair: {}
        )
        model.looking = looking
        _model = State(initialValue: model)
        self.content = content
    }

    var body: some View {
        ZStack {
            BlobBackground()
            ScrollView {
                content(model)
                    .padding(.horizontal, Theme.Spacing.edge)
                    .padding(.top, Theme.Spacing.s32)
            }
        }
    }
}
#endif
