#if VESEL_FAKE_BAND
import Foundation
import VeselCore
import VeselWearable

/// A band that replays synthetic fixtures (made by `ios/Tools/make-fixtures.swift`). Used in the Simulator and in tests.
/// Like the real band, it returns an empty payload for a day it has nothing for, including days it has cleared.
public actor FakeWearableSource: WearableSource {
    // A fixed, always-known zone id.
    public static let fixtureZone = TimeZone(identifier: "Europe/Berlin")!

    private var stored: [FetchKind: [DayKey: BandPayload]]
    private let scenario: FakeScenario
    private let pairingDelay: Duration
    private let liveInterval: Duration
    private let awayWait: Duration
    private let uptime: ManualUptime?
    private var fetchDelay: Duration = .zero
    private var dayDelay: Duration = .zero
    private var hanging: (call: String, duration: Duration)?
    private var hung: [CheckedContinuation<Void, Never>] = []
    /// Calls still hanging from `hangNext`.
    public private(set) var hangsOpen = 0
    private var reachableAfter: Duration?
    private var near = false
    /// How many times a read began looking for it while it was out of reach.
    public private(set) var searches = 0
    private let eventContinuation: AsyncStream<BandEvent>.Continuation
    public nonisolated let events: AsyncStream<BandEvent>
    public nonisolated let links = AsyncStream<BandLink> { $0.finish() }
    /// True while the live heart-rate stream runs.
    public private(set) var isStreaming = false
    private var failure: FakeFailure?
    private var failingKind: FetchKind?
    private var missing: [FetchKind: Set<DayKey>] = [:]
    private var dropping: (kind: FetchKind, reconnects: Bool)?
    private var lost = false
    public private(set) var drops = 0
    public private(set) var profile: Profile?
    public private(set) var wrist: WristSide?
    public private(set) var sleepStatus: SleepRecordingStatus = .stopped
    /// Every call in order, for tests that check what happened when.
    public private(set) var calls: [String] = []
    private var workouts: [BandWorkout]
    /// The Loop's training detection; nil when it has none set.
    public private(set) var detection: WorkoutDetection?
    private var status: WorkoutStatus = .notRunning
    private let now: @Sendable () -> Date

    /// `awayWait`: how long it keeps looking before saying it isn't nearby, at most the read's own wait. Zero in tests; the
    /// Simulator looks as long as the read waits, like the Loop. With an `uptime` (the same one the `BandSync` reads), its
    /// delays and hangs move that instead of taking real time.
    public init(
        scenario: FakeScenario, failure: FakeFailure? = nil, pairingDelay: Duration = .zero, liveInterval: Duration = .seconds(1),
        awayWait: Duration = .zero, uptime: ManualUptime? = nil, now: @escaping @Sendable () -> Date = { Date() }
    ) throws {
        var stored: [FetchKind: [DayKey: BandPayload]] = [:]
        for kind in FetchKind.allCases {
            stored[kind] = Dictionary(uniqueKeysWithValues: try Self.load(kind, scenario: scenario).map { ($0.day, $0) })
        }
        self.stored = try Self.shaped(stored, for: scenario)
        self.scenario = scenario
        self.failure = failure ?? (scenario == .unreachable ? .unreachable : nil)
        if scenario == .stillAsleep { sleepStatus = .recording }
        if scenario == .slowRead { fetchDelay = .seconds(3) }
        self.pairingDelay = pairingDelay
        self.liveInterval = liveInterval
        self.awayWait = awayWait
        self.uptime = uptime
        self.now = now
        workouts = [.firstDay, .firstNight].contains(scenario) ? [] : try Self.loadWorkouts()
        (events, eventContinuation) = AsyncStream.makeStream()
        if scenario == .workoutRunning {
            Task { await self.actOutWorkout() }
        }
    }

    public var connectionState: ConnectionState {
        failure == .unreachable ? .disconnected : .connected
    }

    public func connect(_ deviceId: String) {
        calls.append("connect")
    }

    /// Looks until it comes near (`comesNear`, `comeNear`), the look runs out or the read is stopped.
    public func reachable(within wait: Duration) async -> Bool {
        guard failure == .unreachable else { return true }
        searches += 1
        let start = ContinuousClock.now
        let nearAt = reachableAfter.flatMap { $0 <= wait ? start + $0 : nil }
        let deadline = nearAt ?? start + min(wait, awayWait)
        while !near && ContinuousClock.now < deadline {
            guard (try? await Task.sleep(for: .milliseconds(5))) != nil else { return false }
        }
        guard near || nearAt != nil else { return false }
        near = false
        failure = nil
        reachableAfter = nil
        return true
    }

    public func pair() async throws -> PairedBand {
        calls.append("pair")
        try await Task.sleep(for: pairingDelay)
        switch failure {
        case .notFound: throw PairingError.notFound
        case .refused: throw PairingError.refused
        default: return PairedBand(deviceId: "FAKE0001", name: "Polar Loop")
        }
    }

    public func cancelPairing() {
        calls.append("cancelPairing")
    }

    public func firstTimeUse(_ profile: Profile, now: Date) throws {
        calls.append("firstTimeUse")
        if failure == .setupFailed { throw PairingError.setupFailed }
        self.profile = profile
    }

    public func setWrist(_ wrist: WristSide) throws {
        calls.append("setWrist")
        if failure == .wristFailed { throw BandWriteError.refused }
        self.wrist = wrist
    }

    public func startSync() throws {
        calls.append("startSync")
        lost = false
    }

    public func stopSync() {
        calls.append("stopSync")
    }

    public func setTime(_ date: Date, zone: TimeZone) {
        calls.append("setTime")
    }

    public func battery() -> Int {
        calls.append("battery")
        return scenario == .lowBattery ? 18 : 76
    }

    public func diskSpace() -> DiskSpace {
        calls.append("diskSpace")
        return scenario == .bandFull
            ? DiskSpace(freeBytes: 2_560_000, totalBytes: 16_000_000)
            : DiskSpace(freeBytes: 12_000_000, totalBytes: 16_000_000)
    }

    public func sleepRecordingStatus() async -> SleepRecordingStatus {
        calls.append("sleepRecordingStatus")
        await hangIfAsked("sleepRecordingStatus")
        return sleepStatus
    }

    public func endSleepRecording() async {
        calls.append("endSleepRecording")
        await hangIfAsked("endSleepRecording")
        sleepStatus = .stopped
    }

    public func fetch(_ kind: FetchKind, from start: DayKey, through end: DayKey, answered: @escaping @Sendable () async -> Void) async throws -> [BandPayload]
    {
        calls.append("fetch \(kind.rawValue)")
        await hangIfAsked("fetch \(kind.rawValue)")
        if fetchDelay > .zero { try await take(fetchDelay) }
        if dayDelay > .zero {
            var day = start
            while day <= end {
                try await take(dayDelay)
                await answered()
                day = day.adding(days: 1)
            }
        }
        if kind == failingKind || lost { throw FakeBandError.disconnected }
        let dropped = dropping?.kind == kind
        if let dropping, dropped {
            drops += 1
            lost = !dropping.reconnects
            self.dropping = nil
        }
        var payloads: [BandPayload] = []
        var day = start
        while day <= end {
            if !missing[kind, default: []].contains(day) {
                let empty = BandPayload.empty(day: day, kind: kind, utcOffsetSeconds: Self.offset(day))
                payloads.append(dropped ? empty : stored[kind]?[day] ?? empty)
            }
            day = day.adding(days: 1)
        }
        return payloads
    }

    public func deleteStored(_ type: StoredDataType, until day: DayKey) {
        calls.append("delete \(type.rawValue) until \(day)")
        for kind in type.fetchKinds {
            stored[kind] = stored[kind]?.filter { $0.key > day }
        }
    }

    public func factoryReset() {
        calls.append("factoryReset")
        stored = [:]
        profile = nil
    }

    public func watchBand() {
        calls.append("watchBand")
    }

    public func workoutDetection() -> WorkoutDetection? {
        calls.append("workoutDetection")
        return detection
    }

    public func setWorkoutDetection(_ detection: WorkoutDetection) throws {
        calls.append("setWorkoutDetection")
        if failure == .workoutDetection { throw FakeBandError.refused }
        self.detection = detection
    }

    public func workoutStatus() -> WorkoutStatus {
        calls.append("workoutStatus")
        return status
    }

    public func workoutReferences() -> [WorkoutReference] {
        calls.append("workoutReferences")
        return workouts.map { band in
            WorkoutReference(session: band.workout.session, date: band.workout.start, fileSize: band.workout.fileSize)
        }
    }

    public func workout(_ reference: WorkoutReference) async throws -> BandWorkout {
        calls.append("workout \(reference.session)")
        await hangIfAsked("workout \(reference.session)")
        guard let band = workouts.first(where: { $0.workout.session == reference.session }) else { throw WorkoutReadError.notListed }
        if failure == .workoutTransfer, band.workout.bandSportId == nil { throw FakeBandError.disconnected }
        if band.workout.durationSeconds == 0 { throw WorkoutReadError.unfinished }
        return band
    }

    /// A synthetic heart rate around 62 bpm, one reading per `liveInterval`.
    public func startLiveHeartRate() throws -> AsyncThrowingStream<LiveHeartRate, Error> {
        calls.append("startLiveHeartRate")
        isStreaming = true
        let interval = liveInterval
        return AsyncThrowingStream { continuation in
            let task = Task {
                var tick = 0
                while !Task.isCancelled {
                    let bpm = 62 + [0, 1, 3, 2, -1, -2, 1, 4][tick % 8]
                    continuation.yield(LiveHeartRate(bpm: bpm, skinContact: true, time: Date()))
                    tick += 1
                    try? await Task.sleep(for: interval)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func stopLiveHeartRate() {
        calls.append("stopLiveHeartRate")
        isStreaming = false
    }

    // MARK: Acting out situations

    /// Each fetch takes this long.
    public func setFetchDelay(_ delay: Duration) {
        fetchDelay = delay
    }

    /// Each day of a fetch takes this long and answers when it's done, like the Polar SDK's one request per day.
    public func setDayDelay(_ delay: Duration) {
        dayDelay = delay
    }

    /// The next call starting with `call` ("fetch", "fetch ppi", "sleepRecordingStatus", "endSleepRecording", "workout <session>") doesn't
    /// answer until `answerHangs()` and ignores being stopped, like an SDK call that hangs. `duration` passes on the uptime.
    public func hangNext(_ call: String, for duration: Duration = .zero) {
        hanging = (call, duration)
    }

    /// The hanging calls answer.
    public func answerHangs() {
        for continuation in hung { continuation.resume() }
        hung = []
    }

    private func hangIfAsked(_ call: String) async {
        guard let hanging, call.hasPrefix(hanging.call) else { return }
        self.hanging = nil
        hangsOpen += 1
        defer { hangsOpen -= 1 }
        _ = uptime?.advance(by: hanging.duration)
        await withCheckedContinuation { hung.append($0) }
    }

    /// Real time, or on the uptime: it moves on, and this returns once the read's watchdog has looked at it.
    private func take(_ duration: Duration) async throws {
        guard let uptime else { return try await Task.sleep(for: duration) }
        let readsBefore = uptime.advance(by: duration)
        while uptime.timesRead == readsBefore { try await Task.sleep(for: .milliseconds(1)) }
    }

    public func setSleepStatus(_ status: SleepRecordingStatus) {
        sleepStatus = status
    }

    public func setFailure(_ failure: FakeFailure?) {
        self.failure = failure
    }

    /// Out of reach now; comes near `delay` after a read starts waiting for it.
    public func comesNear(after delay: Duration) {
        failure = .unreachable
        reachableAfter = delay
    }

    /// Comes near now, for a read that is looking for it.
    public func comeNear() {
        near = true
    }

    /// The next fetches of `kind` fail, as if the band disconnected mid-sync.
    public func failFetching(_ kind: FetchKind?) {
        failingKind = kind
    }

    /// The next read drops the connection while fetching `kind`: it comes back all empty, as the Polar SDK reports a
    /// failed file. Later fetches in that read throw, or succeed when the band `reconnects` at once.
    public func dropMidway(_ kind: FetchKind, reconnects: Bool) {
        dropping = (kind, reconnects)
    }

    /// The band was off the wrist these days: they come back empty.
    public func notWorn(_ days: [DayKey]) {
        for kind in FetchKind.allCases {
            for day in days {
                stored[kind]?[day] = nil
            }
        }
    }

    /// `kind` comes back without these days at all, not even empty.
    public func leaveOut(_ kind: FetchKind, days: [DayKey]) {
        missing[kind, default: []].formUnion(days)
    }

    public func clearCalls() {
        calls = []
    }

    public func setDetection(_ detection: WorkoutDetection?) {
        self.detection = detection
    }

    public func setWorkoutStatus(_ status: WorkoutStatus) {
        self.status = status
    }

    /// Adds a workout to the band, or replaces the one with its session.
    public func putWorkout(_ workout: BandWorkout) {
        workouts.removeAll { $0.workout.session == workout.workout.session }
        workouts.append(workout)
    }

    public var workoutSessions: [String] { workouts.map(\.workout.session) }

    /// `workoutRunning`: the Loop starts a workout 5 s after launch and ends it 2 minutes later, then has it like the morning run.
    private func actOutWorkout() async {
        try? await Task.sleep(for: .seconds(5))
        let start = now()
        status = .running(since: start)
        eventContinuation.yield(.workoutStarted(at: start))
        try? await Task.sleep(for: .seconds(120))
        let end = now()
        status = .notRunning
        if var band = workouts.last {
            let format = Date.VerbatimFormatStyle(
                format: "\(year: .defaultDigits)\(month: .twoDigits)\(day: .twoDigits)/\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)",
                timeZone: Self.fixtureZone, calendar: Calendar(identifier: .gregorian)
            )
            band.workout.session = start.formatted(format)
            band.workout.start = start
            band.workout.end = end
            band.workout.utcOffsetSeconds = Self.fixtureZone.secondsFromGMT(for: start)
            band.workout.durationSeconds = Int(end.timeIntervalSince(start))
            let seconds = band.workout.durationSeconds
            band.workout.heartRates = band.workout.heartRates.map { WorkoutHeartRates(intervalMs: $0.intervalMs, bpm: Array($0.bpm.prefix(seconds))) }
            workouts.append(band)
        }
        eventContinuation.yield(.workoutEnded(at: end))
    }

    /// The scenario's own cut of the fixtures: the first nights only, or no sleep at all.
    private static func shaped(_ stored: [FetchKind: [DayKey: BandPayload]], for scenario: FakeScenario) throws -> [FetchKind: [DayKey: BandPayload]] {
        switch scenario {
        case .firstDay:
            let last = DayKey(year: 2026, month: 9, day: 29)
            return stored.mapValues { days in days.filter { $0.key <= last } }
        case .firstNight:
            let last = DayKey(year: 2026, month: 9, day: 26)
            return stored.mapValues { days in days.filter { $0.key <= last } }
        case .stressLearning:
            var result = stored
            result[.ppi] = stored[.ppi]?.filter { $0.key >= DayKey(year: 2026, month: 10, day: 23) }
            return result
        case .offDay:
            var result = stored
            var recharges = stored[.nightlyRecharge] ?? [:]
            for (night, indicator, rmssd) in [(DayKey(year: 2026, month: 10, day: 24), 2, 29), (DayKey(year: 2026, month: 10, day: 25), 1, 27)] {
                recharges[night] = try recharges[night].map { try poor($0, indicator: indicator, rmssd: rmssd) }
            }
            result[.nightlyRecharge] = recharges
            return result
        case .longNight:
            var result = stored
            var nights = stored[.sleep] ?? [:]
            if let last = nights.keys.max() {
                nights[last] = try nights[last].map(longer)
            }
            result[.sleep] = nights
            var recharges = stored[.nightlyRecharge] ?? [:]
            if let last = recharges.keys.max() {
                recharges[last] = try recharges[last].map { try poor($0, indicator: 5, rmssd: 47) }
            }
            result[.nightlyRecharge] = recharges
            return result
        case .noSleep:
            var result = stored
            result[.sleep] = [:]
            result[.nightlyRecharge] = [:]
            return result
        default:
            return stored
        }
    }

    private static let longNightExtra: TimeInterval = 150 * 60

    /// The night ends 150 minutes later, all of it asleep: a light phase is added when it used to end awake.
    private static func longer(_ payload: BandPayload) throws -> BandPayload {
        var object = try jsonObject(payload)
        let format = ISO8601DateFormatter()
        guard let start = (object["sleepStartTime"] as? String).flatMap(format.date(from:)),
            let end = (object["sleepEndTime"] as? String).flatMap(format.date(from:)),
            var phases = object["sleepWakePhases"] as? [[String: Any]]
        else { throw FakeBandError.badFixture }
        format.timeZone = TimeZone(secondsFromGMT: payload.utcOffsetSeconds)
        object["sleepEndTime"] = format.string(from: end.addingTimeInterval(longNightExtra))
        if phases.last?["state"] as? String == "WAKE" {
            phases.append(["secondsFromSleepStart": Int(end.timeIntervalSince(start)), "state": "LIGHT"])
        }
        object["sleepWakePhases"] = phases
        return try changed(payload, to: object)
    }

    private static func poor(_ payload: BandPayload, indicator: Int, rmssd: Int) throws -> BandPayload {
        var object = try jsonObject(payload)
        object["recoveryIndicator"] = indicator
        object["meanNightlyRecoveryRMSSD"] = rmssd
        return try changed(payload, to: object)
    }

    private static func jsonObject(_ payload: BandPayload) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: Data(payload.json.utf8)) as? [String: Any] else { throw FakeBandError.badFixture }
        return object
    }

    private static func changed(_ payload: BandPayload, to object: [String: Any]) throws -> BandPayload {
        var changed = payload
        changed.json = String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
        return changed
    }

    private static func offset(_ day: DayKey) -> Int {
        fixtureZone.secondsFromGMT(for: day.start(in: fixtureZone).addingTimeInterval(12 * 3600))
    }

    private struct WorkoutEntry: Decodable {
        var session: String
        var start: String
        var utcOffsetSeconds: Int
        var bandSportId: Int?
        var durationSeconds: Int
        var calories: Int
        var cardioLoad: Double
        var cardioLoadRating: Int
        var trainingLoad: Double
        var averageHeartRate: Int
        var maxHeartRate: Int
        var heartRates: WorkoutHeartRates
        var fileSize: Int64
        var files: [File]

        struct File: Decodable {
            var name: String
            var data: Data
        }
    }

    private static func loadWorkouts() throws -> [BandWorkout] {
        guard let url = Bundle.module.url(forResource: "workouts", withExtension: "json", subdirectory: "Fixtures/normal") else {
            throw FakeBandError.badFixture
        }
        return try JSONDecoder().decode([WorkoutEntry].self, from: Data(contentsOf: url)).map { entry in
            let start = try Date(entry.start, strategy: .iso8601)
            return BandWorkout(
                workout: Workout(
                    session: entry.session, start: start, end: start.addingTimeInterval(TimeInterval(entry.durationSeconds)),
                    utcOffsetSeconds: entry.utcOffsetSeconds, bandSportId: entry.bandSportId, durationSeconds: entry.durationSeconds,
                    calories: entry.calories, cardioLoad: entry.cardioLoad, cardioLoadRating: entry.cardioLoadRating,
                    trainingLoad: entry.trainingLoad, averageHeartRate: entry.averageHeartRate, maxHeartRate: entry.maxHeartRate,
                    heartRates: entry.heartRates, fileSize: entry.fileSize, unreadableFiles: []
                ),
                files: entry.files.map { WorkoutFile(name: $0.name, data: $0.data) }
            )
        }
    }

    private struct Entry: Decodable {
        var day: DayKey
        var utcOffsetSeconds: Int
        var sampleCount: Int
    }

    private static func load(_ kind: FetchKind, scenario: FakeScenario) throws -> [BandPayload] {
        guard let url = Bundle.module.url(forResource: kind.rawValue, withExtension: "json", subdirectory: "Fixtures/\(scenario.fixtures)") else {
            throw FakeBandError.badFixture
        }
        let data = try Data(contentsOf: url)
        let entries = try JSONDecoder().decode([Entry].self, from: data)
        guard let objects = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw FakeBandError.badFixture }
        return try zip(entries, objects).map { entry, object in
            guard let content = object["payload"] else { throw FakeBandError.badFixture }
            let payload = try JSONSerialization.data(withJSONObject: content, options: [.sortedKeys])
            return BandPayload(
                day: entry.day,
                kind: kind,
                json: String(decoding: payload, as: UTF8.self),
                utcOffsetSeconds: entry.utcOffsetSeconds,
                sampleCount: entry.sampleCount
            )
        }
    }
}

public enum FakeBandError: Error {
    case disconnected
    case badFixture
    case refused
}
#endif
