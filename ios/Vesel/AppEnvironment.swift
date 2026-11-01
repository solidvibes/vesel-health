import Foundation
import Observation
import VeselCore
import VeselStorage
import VeselSync
import VeselWearable
#if DEBUG
import VeselWearableTesting
#endif

/// Wires the database and the band for the whole app. The Simulator has no Bluetooth, so Debug builds there run on the fake band.
/// Built by `AppStartup` when the app delegate is, before launch finishes: Bluetooth state restoration and background tasks need that.
@MainActor
@Observable
final class AppEnvironment {
    let database: AppDatabase
    let clock: any VeselClock
    let bandSync: BandSync
    let pipeline: SyncPipeline
    /// Sync now and I'm up, which keep reading after you leave Vesel.
    let continuedRead: ContinuedRead
    let liveHeartRate: LiveHeartRateController
    let status: SyncStatusStore
    let units = UnitsStore()
    let launch: LaunchOptions
    /// Where Vesel keeps its small settings outside the database.
    let defaults: UserDefaults
    let days: DaySelection
    let router: AppRouter
    /// Nil until the database has been read.
    private(set) var isPaired: Bool?
    /// What setting up the Mac mini backup from `-VeselBackupQR` said, in the Simulator (it has no camera).
    private(set) var launchBackupError: Backup.SetUpError?
    private let wake = BandWakeHandler()
    @ObservationIgnored private var launchScrub: ScrubTime?
    private var launching: Task<Void, Never>?
    @ObservationIgnored private var observingUnits = false

    init(database: AppDatabase, band: any WearableSource, clock: any VeselClock, launch: LaunchOptions, defaults: UserDefaults) {
        self.database = database
        self.clock = clock
        self.launch = launch
        self.defaults = defaults
        launchScrub = launch.scrub
        status = SyncStatusStore(defaults: defaults)
        bandSync = BandSync(band: band, database: database, clock: clock)
        pipeline = SyncPipeline(bandSync: bandSync, database: database, clock: clock, status: status)
        continuedRead = ContinuedRead(pipeline: pipeline, database: database)
        liveHeartRate = LiveHeartRateController(bandSync: bandSync)
        days = DaySelection(clock: clock, chosen: launch.day)
        router = AppRouter(clock: clock)
    }

    /// The app's own: the shared database and the Loop, or the fake band in the Simulator.
    static func live() throws -> AppEnvironment {
        #if DEBUG
        if let error = LaunchOptions.storageProblem(defaults: .standard) { throw error }
        #endif
        let database = try AppDatabase.shared()
        let clock = makeClock()
        #if DEBUG && targetEnvironment(simulator)
        let band: any WearableSource = try FakeWearableSource(
            scenario: FakeScenario(),
            failure: FakeFailure(defaults: .standard),
            pairingDelay: .seconds(2),
            awayWait: .seconds(60)
        )
        #else
        let band: any WearableSource = PolarWearableSource(clock: clock)
        #endif
        return AppEnvironment(database: database, band: band, clock: clock, launch: LaunchOptions(defaults: .standard), defaults: .standard)
    }

    /// The time `-VeselScrub` asks for; the first scrubbable chart shown takes it.
    func takeLaunchScrub() -> ScrubTime? {
        defer { launchScrub = nil }
        return launchScrub
    }

    /// The Simulator can pretend it is another moment with `-VeselNow <ISO 8601>`, in the fixtures' time zone, so
    /// the fixture nights line up with "today".
    private static func makeClock() -> any VeselClock {
        #if DEBUG && targetEnvironment(simulator)
        if let text = UserDefaults.standard.string(forKey: "VeselNow"), let moment = try? Date(text, strategy: .iso8601) {
            return ShiftedClock(offset: moment.timeIntervalSinceNow, timeZone: FakeWearableSource.fixtureZone)
        }
        #endif
        return SystemClock()
    }

    /// Once the database is open: from `didFinishLaunching`, also when iOS launches Vesel in the background for a band
    /// event or a refresh, or later when `AppStartup` opens the database on a retry.
    func didFinishLaunching() {
        BackgroundScheduler.schedule()
        Task { await BackgroundScheduler.scheduleLongRead() }
        Task { await ContinuedRead.clearStale() }
        observeUnits()
        launching = Task {
            #if DEBUG && targetEnvironment(simulator)
            launchBackupError = await SimulatorSetup.prepare(database: database, clock: clock)
            #endif
            let band = try? await database.band()
            isPaired = band != nil
            // What the band said at the last sync, so Today knows a night is still recording before the first read.
            status.set(sleep: (try? await database.setting(AppDatabase.sleepStatusKey)).flatMap(SleepRecordingStatus.init(rawValue:)), at: clock.now)
            wake.start(self)
            if let band {
                await bandSync.connect(band.deviceId)
            }
        }
    }

    /// Syncs when the app comes to the front, unless a read finished under 5 minutes ago and the night is over (`SyncGap`). A Loop paired before
    /// alerts existed gets the notification question here, once.
    func foreground() async {
        observeUnits()
        await launching?.value
        guard isPaired == true else { return }
        Task { await AlertNotifier.askPermissionOnce() }
        await pipeline.run(.foreground, onlyIfDue: true)
    }

    /// The "Sync Vesel" Shortcut, run in the background by iOS. Nil when no Loop is paired.
    func shortcutSync() async -> ShortcutResult? {
        await launching?.value
        guard isPaired == true else { return nil }
        return await ShortcutSync(pipeline: pipeline, database: database, clock: clock).run()
    }

    /// Starts following the units setting unless it already is; a read that ended starts again here.
    private func observeUnits() {
        guard !observingUnits else { return }
        observingUnits = true
        Task { [units, database] in
            await units.observe(database)
            observingUnits = false
        }
    }

    /// A sync iOS woke Vesel for. Nil when no Loop is paired.
    func backgroundSync(_ trigger: SyncTrigger) async -> SyncOutcome? {
        await launching?.value
        guard isPaired == true else { return nil }
        return await pipeline.run(trigger)
    }

    /// The Loop's inactivity alert fired at `alertedAt`: a silent "Time to move" if Stand-up reminders are on, it's not
    /// quiet hours (22:00–07:00) and it isn't over 5 minutes late. Runs beside the band's event queue, never behind a read.
    func standUpReminder(alertedAt: Date) async {
        await launching?.value
        guard isPaired == true, StandUp.isTimely(alertedAt, now: clock.now) else { return }
        let time = BackgroundTime.begin("Stand-up reminder", database: database) {}
        if (try? await database.alertSettings())?.isOn(.standUp) == true,
            case .now = AlertTiming.delivery(at: clock.now, in: clock.timeZone)
        {
            await AlertNotifier(database: database, clock: clock).standUp(StandUp.alert(day: clock.today))
        }
        time.end()
    }

    /// A read on a background task's own time (`SyncPipeline.runHeld`). Nil when no Loop is paired.
    func heldSync(_ trigger: SyncTrigger) async -> SyncOutcome? {
        await launching?.value
        guard isPaired == true else { return nil }
        return await pipeline.runHeld(trigger)
    }

    func didPair() {
        isPaired = true
        Task { await AlertNotifier.askPermissionOnce() }
        Task {
            await bandSync.bandConnected()
            await pipeline.run(.paired)
        }
    }

    func didForget() {
        isPaired = false
    }
}
