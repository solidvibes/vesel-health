import Foundation
import VeselCore
import VeselStorage

/// Reads the band into the database, then clears what is safely stored. Every band call goes through here,
/// one after another: syncs, the live heart-rate stream, pairing, first-time setup and factory reset.
/// One sync at a time; a second trigger while one runs waits for it. The live stream pauses for every sync.
public actor BandSync {
    private let band: any WearableSource
    private let database: AppDatabase
    private let clock: any VeselClock
    private let limits: ReadLimits
    private let uptime: @Sendable () -> ContinuousClock.Instant
    private var running: Task<SyncOutcome, Never>?
    /// The band call now running: its token, when it last heard from the band, and how long it may go without.
    private var timer: (token: Int, since: ContinuousClock.Instant, limit: Duration)?
    private var tokens = 0
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var wantsLive = false
    private var live: Task<Void, Never>?
    private var liveGeneration = 0
    private let liveContinuation: AsyncStream<LiveHeartRate>.Continuation
    /// Live heart rate while it is on. For showing only: never store or log it.
    public nonisolated let liveHeartRate: AsyncStream<LiveHeartRate>
    /// What the band says on its own.
    public nonisolated var events: AsyncStream<BandEvent> { band.events }
    /// Each change in the Bluetooth link to the band.
    public nonisolated var links: AsyncStream<BandLink> { band.links }

    /// `uptime` is the time `limits` are measured on: the phone's own, which a clock change can't move. Tests move theirs by hand.
    public init(
        band: any WearableSource, database: AppDatabase, clock: any VeselClock, limits: ReadLimits = .standard,
        uptime: @escaping @Sendable () -> ContinuousClock.Instant = { .now }
    ) {
        self.band = band
        self.database = database
        self.clock = clock
        self.limits = limits
        self.uptime = uptime
        (liveHeartRate, liveContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    /// `progress` hears each step as the read goes and is awaited, so every report lands before this returns. A trigger
    /// that joins a running sync hears nothing. It waits for the Loop as long as `limits` says for the trigger, or `loopWait`.
    @discardableResult
    public func sync(
        _ trigger: SyncTrigger, loopWait: Duration? = nil, progress: @escaping @Sendable (SyncStep) async -> Void = { _ in }
    ) async -> SyncOutcome {
        if let running {
            return await running.value
        }
        let wait = loopWait ?? limits.loopWait(trigger)
        let task = Task { await exclusively { await self.run(trigger, wait: wait, progress: progress) } }
        running = task
        let outcome = await task.value
        running = nil
        return outcome
    }

    /// Stops a running sync, e.g. when iOS ends the app's background time. Nothing is cleared from the band after this.
    public func cancelSync() {
        running?.cancel()
    }

    public func connectionState() async -> ConnectionState {
        await band.connectionState
    }

    public func connect(_ deviceId: String) async {
        await band.connect(deviceId)
    }

    /// After the band (re)connects: listen for its notices again and resume the live stream if it is wanted.
    public func bandConnected() async {
        await exclusively {
            await self.band.watchBand()
            await self.resumeLive()
        }
    }

    public func startLiveHeartRate() async {
        wantsLive = true
        await exclusively { await self.resumeLive() }
    }

    public func stopLiveHeartRate() async {
        wantsLive = false
        await exclusively { await self.pauseLive() }
    }

    public var isStreaming: Bool { live != nil }

    /// What the band said about sleep at the last sync, or after the owner ended the night. Nil before the first sync.
    public private(set) var sleepStatus: SleepRecordingStatus?

    /// How long a read for `trigger` waits for the Loop.
    public nonisolated func loopWait(_ trigger: SyncTrigger) -> Duration {
        limits.loopWait(trigger)
    }

    /// Asks the band whether it still records sleep, queued like every band call, after waiting up to `wait` for it. Nil
    /// when it isn't nearby.
    /// A call the band never answers counts as not nearby.
    public func readSleepStatus(within wait: Duration) async -> SleepRecordingStatus? {
        let status = await exclusively { () async -> SleepRecordingStatus? in
            guard await self.band.reachable(within: wait) else { return nil }
            return try? await self.guarded(drops: await self.band.drops) {
                (try? await self.call { _ in try await self.band.sleepRecordingStatus() }) ?? .unknown
            }
        }
        if let status { sleepStatus = status }
        return status
    }

    /// The owner got up: ends the band's sleep recording, in line with every other band call. Syncs never call this.
    public func endSleepRecording() async throws {
        try await exclusively {
            try await self.guarded(drops: await self.band.drops) {
                try await self.call { _ in try await self.band.endSleepRecording() }
            }
        }
        sleepStatus = .stopped
    }

    public func pair() async throws -> PairedBand {
        try await exclusively { try await self.band.pair() }
    }

    /// Not queued: it has to interrupt a pairing in progress.
    public func cancelPairing() async {
        await band.cancelPairing()
    }

    /// Writes the profile to the band (Polar's first-time setup). The live stream pauses for it and comes back after,
    /// also when the band refuses. A cancelled caller stops before the write starts.
    public func firstTimeUse(_ profile: Profile) async throws {
        try await exclusively {
            await self.pauseLive()
            do {
                try Task.checkCancellation()
                try await self.band.firstTimeUse(profile, now: self.clock.now)
            } catch {
                await self.resumeLive()
                throw error
            }
            await self.resumeLive()
        }
    }

    /// Tells the band which wrist it is worn on, once no sync is running.
    public func setWrist(_ wrist: WristSide) async throws {
        try await exclusively {
            try Task.checkCancellation()
            try await self.band.setWrist(wrist)
        }
    }

    /// Wipes the band, its pairing included, once no sync is running.
    public func factoryReset() async throws {
        try await exclusively {
            await self.pauseLive()
            try await self.band.factoryReset()
        }
    }

    // MARK: One band call at a time

    private func exclusively<T: Sendable>(_ work: @Sendable () async throws -> T) async rethrows -> T {
        if busy {
            await withCheckedContinuation { waiting.append($0) }
        } else {
            busy = true
        }
        defer {
            if waiting.isEmpty {
                busy = false
            } else {
                waiting.removeFirst().resume()
            }
        }
        return try await work()
    }

    private func resumeLive() async {
        guard wantsLive, live == nil, let values = try? await band.startLiveHeartRate() else { return }
        liveGeneration += 1
        let generation = liveGeneration
        live = Task { [liveContinuation] in
            do {
                for try await value in values { liveContinuation.yield(value) }
            } catch {}
            self.liveEnded(generation)
        }
    }

    private func pauseLive() async {
        guard let live else { return }
        live.cancel()
        self.live = nil
        await band.stopLiveHeartRate()
    }

    /// The band ended the stream itself (e.g. it disconnected); `bandConnected` starts it again.
    private func liveEnded(_ generation: Int) {
        if generation == liveGeneration { live = nil }
    }

    private func run(_ trigger: SyncTrigger, wait: Duration, progress: @escaping @Sendable (SyncStep) async -> Void) async -> SyncOutcome {
        let startedAt = clock.now
        guard let runId = try? await database.startSyncRun(trigger, at: startedAt) else { return .failed }
        await pauseLive()
        let (outcome, detail) = await readBand(wait: wait, progress: progress)
        await resumeLive()
        // Recorded even when the sync was stopped: a cancelled task can't write to the database.
        let database = database
        let finishedAt = clock.now
        await Task.detached { try? await database.finishSyncRun(runId, outcome: outcome, detail: detail, at: finishedAt) }.value
        return outcome
    }

    private func readBand(wait: Duration, progress: @escaping @Sendable (SyncStep) async -> Void) async -> (SyncOutcome, String?) {
        guard let info = try? await database.band() else { return (.failed, SyncDetail.notPaired) }
        if await band.connectionState != .connected { await progress(.waitingForLoop) }
        guard await band.reachable(within: wait) else {
            return (.unreachable, Task.isCancelled ? SyncDetail.stoppedEarly : SyncDetail.notNearby)
        }
        let drops = await band.drops
        // A read the guard stopped may still be running behind it: its steps no longer reach anyone.
        let live: @Sendable (SyncStep) async -> Void = { step in
            if !Task.isCancelled { await progress(step) }
        }
        let outcome: (SyncOutcome, String?)
        do {
            try await guarded(drops: drops) {
                do {
                    try await self.call { _ in try await self.band.startSync() }
                } catch {
                    throw NotStarted()
                }
                await live(.loopFound)
                try await self.fetchStoreAndClear(info, drops: drops, progress: live)
            }
            outcome = (.success, nil)
        } catch is NotStarted {
            return (.unreachable, SyncDetail.didNotStart)
        } catch {
            outcome = (.failed, Self.describe(error))
        }
        try? await band.stopSync()
        return outcome
    }

    private struct NotStarted: Error {}

    /// Runs `work`, and stops it when the Loop drops (its drop count changes, or it stays away longer than `awayGrace`) or
    /// a band call goes without an answer longer than its limit. A stopped call that never returns is left behind, cancelled,
    /// so the work never hangs and never goes on to another band call.
    private func guarded<T: Sendable>(drops: Int, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        let working = Task { try await work() }
        let watching = Task { try await self.watch(drops: drops) }
        defer {
            working.cancel()
            watching.cancel()
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, any Error>) in
                let first = FirstResult(continuation)
                Task {
                    do {
                        first.resume(with: .success(try await working.value))
                    } catch {
                        first.resume(with: .failure(error))
                    }
                }
                Task {
                    do {
                        try await watching.value
                    } catch {
                        first.resume(with: .failure(error))
                    }
                }
            }
        } onCancel: {
            working.cancel()
            watching.cancel()
        }
    }

    private func watch(drops: Int) async throws {
        var awaySince: ContinuousClock.Instant?
        while true {
            try await Task.sleep(for: limits.tick)
            guard await band.drops == drops else { throw BandSyncError.lostBand }
            if await band.connectionState == .connected {
                awaySince = nil
            } else if let awaySince {
                if awaySince.duration(to: uptime()) > limits.awayGrace { throw BandSyncError.lostBand }
            } else {
                awaySince = uptime()
            }
            if let timer, timer.since.duration(to: uptime()) > timer.limit { throw BandSyncError.stuck }
        }
    }

    /// One call to the band, timed for `watch`: it may go `limit` (`stuckCall` by default) without the band answering. A
    /// call that answers in parts (one SDK request per day) restarts the time with each part through `answered`.
    private func call<T: Sendable>(limit: Duration? = nil, _ work: (@escaping @Sendable () async -> Void) async throws -> T) async throws -> T {
        try Task.checkCancellation()
        tokens += 1
        let token = tokens
        timer = (token, uptime(), limit ?? limits.stuckCall)
        defer { if timer?.token == token { timer = nil } }
        return try await work { await self.answered(token) }
    }

    private func answered(_ token: Int) {
        if timer?.token == token { timer?.since = uptime() }
    }

    /// Readings show as each kind arrives; empty days, heart-rate and beat-to-beat ledger rows and clearing only after a
    /// whole read: every fetch returned, the task wasn't cancelled and the band never dropped the connection (`drops`
    /// unchanged), as the Polar SDK reports a file it failed to read as no data. `progress` only listens: it never
    /// changes what is fetched, stored or cleared, or in which order.
    private func fetchStoreAndClear(_ info: BandInfo, drops: Int, progress: @escaping @Sendable (SyncStep) async -> Void) async throws {
        let now = clock.now
        let zone = clock.timeZone
        let today = clock.today
        try await call { _ in try await band.setTime(now, zone: zone) }

        var updated = info
        updated.batteryPercent = try await call { _ in try await band.battery() }
        updated.batteryAt = now
        let disk = try await call { _ in try await band.diskSpace() }
        updated.diskFreeBytes = disk.freeBytes
        updated.diskTotalBytes = disk.totalBytes
        updated.lastSeenAt = now
        try await database.save(updated)

        // Heart rate and beat-to-beat last: each downloads every 24/7 file on the band, however few days are asked for.
        var kinds: [FetchKind] = [.dailySummary, .activitySamples, .skinTemperature, .heartRate, .ppi]
        let sleepStatus = try await call { _ in try await band.sleepRecordingStatus() }
        self.sleepStatus = sleepStatus
        if sleepStatus == .stopped {
            kinds = [.sleep, .nightlyRecharge] + kinds
        }
        await progress(.kinds(kinds))

        let firstDay = DayKey(info.pairedAt, in: zone).adding(days: -1)
        var held: [BandPayload] = []
        for kind in kinds {
            try Task.checkCancellation()
            let ledger = try await database.ledger([kind])
            let afterLast = try await database.lastStoredDay(kind).map { $0.adding(days: -1) }
            let unsettled = ClearPlan.firstUnsettledDay(in: ledger, timeZone: zone)
            let start = [afterLast, unsettled].compactMap { $0 }.min() ?? firstDay
            // Heart rate and beat-to-beat are one SDK request that reads every 24/7 file: it may take longer without a word.
            let limit = kind == .heartRate || kind == .ppi ? limits.backlogCall : nil
            let payloads = try await call(limit: limit) { answered in
                try await band.fetch(kind, from: min(start, today), through: today, answered: answered)
            }.sorted { $0.day < $1.day }
            try Task.checkCancellation()
            if kind == .heartRate || kind == .ppi {
                // A file the SDK failed to read can leave part of a day: shown now, counted only after a whole read.
                try await database.saveReadings(payloads)
                held += payloads
            } else {
                // Each day is one whole record. Nothing past a day never read before that came back empty, so the last
                // stored day never skips a day with no ledger row.
                let known = Set(ledger.map(\.day))
                let cut = payloads.firstIndex { $0.isEmpty && !known.contains($0.day) } ?? payloads.endIndex
                try await database.save(payloads[..<cut].filter { !$0.isEmpty }, fetchedAt: now)
                held += payloads[..<cut].filter(\.isEmpty) + payloads[cut...]
            }
            await progress(.fetched(kind))
        }

        try Task.checkCancellation()
        guard await band.drops == drops else { throw BandSyncError.lostBand }
        for (_, payloads) in Dictionary(grouping: held, by: \.day).sorted(by: { $0.key < $1.key }) {
            try await database.save(payloads, fetchedAt: now)
        }
        guard await band.drops == drops else { throw BandSyncError.lostBand }

        try Task.checkCancellation()
        for type in StoredDataType.allCases {
            try Task.checkCancellation()
            let ledger = try await database.ledger(type.fetchKinds)
            guard let day = ClearPlan.lastSafeDay(for: type, ledger: ledger, today: today, timeZone: zone) else { continue }
            try await call { _ in try await band.deleteStored(type, until: day) }
            for kind in type.fetchKinds {
                try await database.markDeletedFromBand(kind, through: day, at: clock.now)
            }
        }
    }

    /// What went wrong, in words with no health values in them.
    private static func describe(_ error: any Error) -> String {
        switch error {
        case is CancellationError: SyncDetail.stoppedEarly
        case BandPayloadError.unreadable(let kind, let day): "Couldn't read \(kind.rawValue) for \(day)"
        default: "Sync stopped: \(type(of: error))"
        }
    }
}

public enum BandSyncError: Error {
    /// The band dropped the connection during the read, so what came back may be incomplete.
    case lostBand
    /// One call to the band took longer than `ReadLimits.stuckCall`.
    case stuck
}

/// How long a read waits, so a Loop out of reach or a band call that never answers can't hold it for good. Tests make them short.
public struct ReadLimits: Sendable {
    /// Waiting for the Loop when a tap or opening Vesel started the read.
    public var tapWait: Duration
    /// Waiting for the Loop in the background, where iOS gives about 30 seconds.
    public var backgroundWait: Duration
    /// A band call without any answer from the band.
    public var stuckCall: Duration
    /// The heart-rate or beat-to-beat download, one SDK request over every 24/7 file on the band, a backlog included.
    public var backlogCall: Duration
    /// The Loop away during a read without counting a drop.
    public var awayGrace: Duration
    /// How often a read checks on the Loop.
    public var tick: Duration

    public static let standard = ReadLimits(
        tapWait: .seconds(60), backgroundWait: .seconds(20), stuckCall: .seconds(90), backlogCall: .seconds(600), awayGrace: .seconds(15), tick: .seconds(1)
    )

    public init(tapWait: Duration, backgroundWait: Duration, stuckCall: Duration, backlogCall: Duration, awayGrace: Duration, tick: Duration) {
        self.tapWait = tapWait
        self.backgroundWait = backgroundWait
        self.stuckCall = stuckCall
        self.backlogCall = backlogCall
        self.awayGrace = awayGrace
        self.tick = tick
    }

    public func loopWait(_ trigger: SyncTrigger) -> Duration {
        switch trigger {
        case .manual, .imUp, .foreground, .launch, .paired: tapWait
        case .bandEvent, .bandCheckIn, .longRead, .backgroundRefresh, .shortcut: backgroundWait
        }
    }
}

/// Resumes a continuation once, with whichever result comes first.
private final class FirstResult<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, any Error>?

    init(_ continuation: CheckedContinuation<T, any Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<T, any Error>) {
        let continuation = lock.withLock {
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(with: result)
    }
}
