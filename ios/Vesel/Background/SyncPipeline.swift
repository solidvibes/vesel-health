import UIKit
import WidgetKit
import VeselCore
import VeselStorage
import VeselSync
import VeselWearable

/// Everything a sync does, in order: read the band, work out the numbers, send any alerts, back up to the Mac mini.
/// Runs never overlap.
/// Each run asks iOS for background time (or runs on a background task's own, `runHeld`), wakes the database first and lets it sleep again after if the app is in
/// the background, so iOS never suspends Vesel while it holds the database.
actor SyncPipeline {
    private let bandSync: BandSync
    private let database: AppDatabase
    private let clock: any VeselClock
    private let status: SyncStatusStore
    private var running: Task<SyncOutcome?, Never>?
    private var uploading: Task<BackupOutcome?, Never>?
    private var writing: Task<Void, any Error>?

    init(bandSync: BandSync, database: AppDatabase, clock: any VeselClock, status: SyncStatusStore) {
        self.bandSync = bandSync
        self.database = database
        self.clock = clock
        self.status = status
    }

    /// The owner got up. Ends sleep on the band (queued with every other band call), then reads the night.
    /// Only the "Sync Vesel" Shortcut calls this; "I'm up" goes through `ImUpRequest`, delivered before a read.
    @discardableResult
    func endNight(_ trigger: SyncTrigger) async throws -> SyncOutcome? {
        try await endSleep()
        // A sync that began before the night ended skipped sleep; wait it out so a new one reads the night.
        if let running {
            _ = await running.value
            if self.running == running { self.running = nil }
        }
        return await run(trigger)
    }

    /// Ends sleep on the band, queued with every other band call; the read is the caller's.
    func endSleep() async throws {
        try await bandSync.endSleepRecording()
        await status.nightEnded(at: clock.now)
    }

    /// The "Sync Vesel" Shortcut: running it is deliberate, so if the band still records sleep (or can't say, until last
    /// night is stored) the night ends first and is read now rather than up to ~90 minutes later. Nil when the Loop isn't nearby.
    func shortcut() async -> SyncOutcome? {
        guard let sleep = await bandSync.readSleepStatus(within: bandSync.loopWait(.shortcut)) else { return nil }
        let stored = (try? await database.hasNight(clock.today)) == true
        if sleep == .recording || (sleep == .unknown && !stored), let outcome = try? await endNight(.shortcut) {
            return outcome
        }
        return await run(.shortcut)
    }

    /// Returns once no sync is running.
    func idle() async {
        if let running {
            _ = await running.value
        }
    }

    /// Nil when `onlyIfDue` and `SyncGap` says it isn't due.
    @discardableResult
    func run(_ trigger: SyncTrigger, onlyIfDue: Bool = false) async -> SyncOutcome? {
        if let running {
            let outcome = await running.value
            if let outcome, outcome != .unreachable { return outcome }
            if outcome == nil && onlyIfDue { return nil }
            // The running one was skipped as not due, or gave up on the Loop before this trigger (it may have just come
            // near): read afresh.
            if self.running == running { self.running = nil }
            return await run(trigger, onlyIfDue: outcome == .unreachable && onlyIfDue)
        }
        let task = Task { await self.runInBackgroundTime(trigger, onlyIfDue: onlyIfDue) }
        running = task
        let outcome = await task.value
        if running == task { running = nil }
        return outcome
    }

    /// A read on a background task's own time (the long read; Sync now and I'm up once you leave Vesel), outside
    /// `beginBackgroundTask`, whose ~30 s would cut it off. Waits for a running read, then always reads afresh, so
    /// `progress` hears this read's own steps. Cancelling the calling task stops the read (nothing is cleared); the task's
    /// expiration handler also calls `expire()`. Nil when cancelled before the read began.
    func runHeld(_ trigger: SyncTrigger, progress: @escaping @Sendable (SyncStep) async -> Void = { _ in }) async -> SyncOutcome? {
        let time = await BackgroundTime.hold(database: database)
        while let current = running {
            _ = await current.value
            if running == current { running = nil }
        }
        guard !Task.isCancelled else {
            await time.end()
            return nil
        }
        let task = Task { await self.syncIfDue(trigger, onlyIfDue: false, progress: progress) }
        running = task
        let outcome = await withTaskCancellationHandler {
            await task.value
        } onCancel: { [bandSync] in
            task.cancel()
            Task { await bandSync.cancelSync() }
        }
        if running == task { running = nil }
        await time.end()
        return outcome
    }

    /// "Back up now": once no sync is running, in its own background time. Nil when backup isn't set up.
    func backUpNow() async -> BackupOutcome? {
        await idle()
        let time = await BackgroundTime.begin("Back up Vesel", database: database) { [self] in expire() }
        let outcome = await backUp()
        await time.end()
        return outcome
    }

    /// About you was saved: once no sync is running, writes the profile to the band (Polar's first-time setup), then
    /// stores it. False when the band didn't take it or iOS ended the time first; nothing is stored on the phone then.
    func writeProfile(_ profile: Profile) async -> Bool {
        let time = await BackgroundTime.begin("Save to your Loop", database: database) { [self] in expire() }
        // Waits inside the task, so time running out while a sync finishes still stops the write.
        let task = Task { [self, bandSync, database] in
            await idle()
            try await bandSync.firstTimeUse(profile)
            try Task.checkCancellation()
            try await database.save(profile)
        }
        writing = task
        let saved = (try? await task.value) != nil
        if writing == task { writing = nil }
        await time.end()
        return saved
    }

    /// A Workouts setting changed: once no sync is running, writes the Loop's training detection, then stores it. False when
    /// the band didn't take it or iOS ended the time first; nothing is stored on the phone then.
    func writeWorkoutDetection(_ detection: WorkoutDetection) async -> Bool {
        let time = await BackgroundTime.begin("Save to your Loop", database: database) { [self] in expire() }
        let task = Task { [self, bandSync, database] in
            await idle()
            try await bandSync.setWorkoutDetection(detection)
            try Task.checkCancellation()
            try await database.storeWorkoutDetection(detection)
        }
        writing = task
        let saved = (try? await task.value) != nil
        if writing == task { writing = nil }
        await time.end()
        return saved
    }

    /// iOS is about to suspend Vesel: stop the sync (nothing gets cleared), the backup and a profile write that hasn't
    /// reached the band yet, and let go of the database.
    nonisolated func expire() {
        let bandSync = bandSync
        Task { await bandSync.cancelSync() }
        Task { await self.cancelForExpiry() }
        database.suspend()
    }

    /// Also the running read itself, so a wait for the Loop (an "I'm up" waiting to be delivered) doesn't carry on later.
    private func cancelForExpiry() {
        running?.cancel()
        uploading?.cancel()
        writing?.cancel()
    }

    /// Runs last: it never changes how the band sync went, and its outcome is kept apart from the sync runs.
    private func backUp() async -> BackupOutcome? {
        let task = Task { [database, clock] in await Backup.run(database: database, clock: clock) }
        uploading = task
        let outcome = await task.value
        if uploading == task { uploading = nil }
        return outcome
    }

    #if DEBUG
    /// For the band data report: whether the live heart-rate stream runs.
    var isStreaming: Bool {
        get async { await bandSync.isStreaming }
    }

    /// For the band data report: how densely the band recorded, per hour, in the phone's time zone.
    func bandDataReport(from first: DayKey, through last: DayKey) async throws -> [BandDataHour] {
        try await database.bandDataReport(from: first, through: last, timeZone: clock.timeZone)
    }
    #endif

    /// The app went to the background: the database sleeps now, or when the running sync ends.
    @MainActor func suspendIfIdle() {
        if BackgroundTime.isIdle { database.suspend() }
    }

    private func runInBackgroundTime(_ trigger: SyncTrigger, onlyIfDue: Bool) async -> SyncOutcome? {
        let time = await BackgroundTime.begin("Sync Vesel", database: database) { [self] in expire() }
        let outcome = await syncIfDue(trigger, onlyIfDue: onlyIfDue)
        await time.end()
        return outcome
    }

    private func storedSleepStatus() async -> SleepRecordingStatus? {
        (try? await database.setting(AppDatabase.sleepStatusKey)).flatMap(SleepRecordingStatus.init(rawValue:))
    }

    private func syncIfDue(_ trigger: SyncTrigger, onlyIfDue: Bool, progress: @escaping @Sendable (SyncStep) async -> Void = { _ in }) async -> SyncOutcome? {
        let now = clock.now
        if let imUp = await status.imUp {
            let stored = (try? await database.hasNight(clock.today)) == true
            if stored || !imUp.isWaiting(at: now) { await status.clearImUp() }
        }
        // A waiting "I'm up" exists only untried or after the Loop wasn't nearby, so skipping the gap only ever tries the Loop again.
        let endingNight = await status.imUp != nil
        // Also after iOS ended the app: a fresh launch goes by what the band said about sleep at the last sync, stored on the
        // phone; with nothing stored (first launch, a forgotten Loop) the night isn't known to be over, so opening reads.
        if onlyIfDue && !endingNight {
            var sleepStatus = await bandSync.sleepStatus
            if sleepStatus == nil { sleepStatus = await storedSleepStatus() }
            let due = SyncGap.isDue(
                trigger: trigger,
                now: now,
                runs: (try? await database.latestSyncRuns(limit: 20)) ?? [],
                lastFinishedAt: try? await database.lastSuccessfulSync(),
                nightOver: sleepStatus == .stopped
            )
            if !due { return nil }
        }
        await status.set(.reading(SyncProgress()))
        var loopWait = bandSync.loopWait(trigger)
        // Not nearby after the whole wait: the read below only checks once more.
        if endingNight, await !deliverImUp(within: loopWait) { loopWait = .zero }
        if Task.isCancelled {
            await status.set(.idle)
            return nil
        }
        // Awaited inside the sync, so no report can land after the status below.
        let outcome = await bandSync.sync(trigger, loopWait: loopWait) { [status] step in
            await status.report(step)
            await progress(step)
        }
        if outcome != .unreachable {
            _ = try? await MetricsUpdater(database: database, clock: clock).updateAfterSync()
            await status.stressWorkedOut()
            await AlertNotifier(database: database, clock: clock).update()
            if outcome != .failed { WidgetCenter.shared.reloadAllTimelines() }
        }
        let sleepStatus = await bandSync.sleepStatus
        await status.set(sleep: sleepStatus, at: clock.now)
        if let sleepStatus, await storedSleepStatus() != sleepStatus {
            try? await database.setSettings([AppDatabase.sleepStatusKey: sleepStatus.rawValue])
        }
        // Only a tap that asked for this read hears that the Loop wasn't found; "I'm up" says so on its own card.
        if outcome == .unreachable && trigger == .manual {
            await status.set(.unreachable(lastRead: try? await database.lastSuccessfulSync()))
        } else {
            await status.set(.idle)
        }
        _ = await backUp()
        return outcome
    }

    /// A waiting "I'm up": asks the Loop, then ends its night unless it already stopped, before the read fetches it.
    /// False when the Loop wasn't nearby; the tap is kept for the next read.
    private func deliverImUp(within wait: Duration) async -> Bool {
        if await bandSync.connectionState() != .connected { await status.set(.waitingForLoop) }
        let sleep = await bandSync.readSleepStatus(within: wait)
        // Stopped (iOS ended the time) during the wait: the tap stays as it was.
        guard !Task.isCancelled else { return false }
        guard let sleep else {
            await status.imUpMissedLoop()
            return false
        }
        await status.set(.reading(SyncProgress()))
        // The wait can be long, or paused while iOS suspended Vesel: the tap must still be waiting and last night not in.
        let stillWaiting = await status.imUp?.isWaiting(at: clock.now) == true
        let stored = (try? await database.hasNight(clock.today)) == true
        if sleep == .stopped {
            await status.set(sleep: .stopped, at: clock.now)
        } else if stillWaiting && !stored {
            // A Loop that is near but refuses: the tap goes, and "I'm up" comes back while it still records.
            try? await endSleep()
        }
        await status.clearImUp()
        return true
    }
}

/// Time iOS grants to finish work after the app leaves the screen or is woken in the background. It wakes the
/// database when it begins and lets it sleep when the last one ends in the background. All on the main actor, so
/// this and the scene's resume and suspend never interleave.
@MainActor
final class BackgroundTime {
    private static var open = 0
    static var isIdle: Bool { open == 0 }

    private let database: AppDatabase
    private var id: UIBackgroundTaskIdentifier = .invalid
    private var ended = false

    private init(database: AppDatabase) {
        self.database = database
    }

    static func begin(_ name: String, database: AppDatabase, onExpiry: @escaping @MainActor () -> Void) -> BackgroundTime {
        let time = BackgroundTime(database: database)
        open += 1
        database.resume()
        time.id = UIApplication.shared.beginBackgroundTask(withName: name) {
            // iOS calls the expiration handler on the main thread; the compiler can't see that.
            MainActor.assumeIsolated {
                onExpiry()
                time.end()
            }
        }
        return time
    }

    /// For work on a background task's own time: only the database's wake and sleep, no `beginBackgroundTask`. The task's
    /// expiration handler stops the work.
    static func hold(database: AppDatabase) -> BackgroundTime {
        let time = BackgroundTime(database: database)
        open += 1
        database.resume()
        return time
    }

    /// Runs once: on expiry or when the work is done, whichever comes first.
    func end() {
        guard !ended else { return }
        ended = true
        Self.open -= 1
        if Self.isIdle, UIApplication.shared.applicationState == .background { database.suspend() }
        if id != .invalid { UIApplication.shared.endBackgroundTask(id) }
    }
}
