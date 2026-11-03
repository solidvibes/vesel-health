import Foundation
import VeselCore

/// A band Vesel reads from. The Polar Loop is one; the Simulator uses `FakeWearableSource`.
/// Calls run one at a time, never in parallel; `BandSync` is the only caller during a sync.
public protocol WearableSource: Sendable {
    var connectionState: ConnectionState { get async }
    /// How often the band has dropped the connection since launch. A read is whole only if this didn't change during it.
    var drops: Int { get async }
    /// Reconnects to an already paired band; the band reconnects on its own after that.
    func connect(_ deviceId: String) async
    /// Asks to connect if it isn't, then waits up to `wait` for the band to be connected and ready; false when it didn't
    /// come near in time. With no wait it only checks.
    func reachable(within wait: Duration) async -> Bool
    /// Looks for a band in pairing mode, takes the strongest and connects. iOS shows its pairing prompt.
    func pair() async throws -> PairedBand
    func cancelPairing() async
    func firstTimeUse(_ profile: Profile, now: Date) async throws
    /// Tells the band which wrist it is worn on.
    func setWrist(_ wrist: WristSide) async throws
    /// Tells the band a sync starts: it writes its cached 24/7 data to files.
    func startSync() async throws
    func stopSync() async throws
    func setTime(_ date: Date, zone: TimeZone) async throws
    func battery() async throws -> Int
    func diskSpace() async throws -> DiskSpace
    func sleepRecordingStatus() async throws -> SleepRecordingStatus
    /// Ends the band's sleep recording, as if the owner got up. Only an explicit "I'm up" calls this; a sync never does.
    func endSleepRecording() async throws
    /// One payload per day from `start` through `end`; a day without data comes back empty. `answered` hears each SDK
    /// request that returns along the way, so a long fetch that keeps answering isn't taken for stuck.
    func fetch(_ kind: FetchKind, from start: DayKey, through end: DayKey, answered: @escaping @Sendable () async -> Void) async throws -> [BandPayload]
    /// Clears data of `type` from the band, up to and including `day`. Only after it is safely in the database.
    func deleteStored(_ type: StoredDataType, until day: DayKey) async throws
    /// Wipes the band, its pairing included.
    func factoryReset() async throws
    /// What the band says on its own: it reconnected, a night ended, it asks to sync. One stream for the app's lifetime.
    var events: AsyncStream<BandEvent> { get }
    /// Each change in the Bluetooth link to the band, for the connection log. One stream for the app's lifetime.
    var links: AsyncStream<BandLink> { get }
    /// Listens for the band's notices. Call after each reconnect; the band forgets subscriptions when it disconnects.
    func watchBand() async
    /// Heart rate about once a second, for showing only. Ends when the band disconnects.
    func startLiveHeartRate() async throws -> AsyncThrowingStream<LiveHeartRate, Error>
    func stopLiveHeartRate() async
}

extension WearableSource {
    public func fetch(_ kind: FetchKind, from start: DayKey, through end: DayKey) async throws -> [BandPayload] {
        try await fetch(kind, from: start, through: end, answered: {})
    }
}

public enum BandEvent: Sendable, Equatable {
    case connected
    /// The band stopped recording sleep: the night is over.
    case sleepEnded
    /// The band asks to be synced.
    case syncRequested
    /// The band said something that isn't a sync request: an exercise started or ended, an inactivity warning, a battery
    /// or charging change (also once after every connect). A chance to read, if one is due.
    case checkIn
    /// The band's own inactivity alert fired at this moment: the wearer has been still too long. Also a check-in.
    case stillTooLong(at: Date)
}

/// One live heart-rate reading. Shown, never stored or logged.
public struct LiveHeartRate: Sendable, Equatable {
    public var bpm: Int
    /// Nil when the band doesn't say.
    public var skinContact: Bool?
    public var time: Date

    public init(bpm: Int, skinContact: Bool?, time: Date) {
        self.bpm = bpm
        self.skinContact = skinContact
        self.time = time
    }
}

public enum ConnectionState: Sendable, Equatable {
    case disconnected, connecting, connected
}

public enum SleepRecordingStatus: String, Sendable, Equatable {
    case recording, stopped, unknown
}

public struct PairedBand: Sendable, Equatable {
    public var deviceId: String
    public var name: String

    public init(deviceId: String, name: String) {
        self.deviceId = deviceId
        self.name = name
    }
}

public enum PairingError: Error, Equatable {
    /// No band in pairing mode nearby.
    case notFound
    /// The band or iOS refused the pairing; the band needs a factory reset.
    case refused
    /// Connected, but the band's first-time setup didn't go through.
    case setupFailed
}

/// The band didn't take a setting.
public enum BandWriteError: Error, Equatable {
    case refused
}

/// What the band stores and can clear, each covering one or more fetch kinds.
public enum StoredDataType: String, Sendable, CaseIterable {
    case sleep, nightlyRecharge, autoSample, skinTemperature, activity, dailySummary

    public var fetchKinds: [FetchKind] {
        switch self {
        case .sleep: [.sleep]
        case .nightlyRecharge: [.nightlyRecharge]
        case .autoSample: [.heartRate, .ppi]
        case .skinTemperature: [.skinTemperature]
        case .activity: [.activitySamples]
        case .dailySummary: [.dailySummary]
        }
    }
}

public struct DiskSpace: Sendable, Equatable {
    public var freeBytes: Int64
    public var totalBytes: Int64

    public init(freeBytes: Int64, totalBytes: Int64) {
        self.freeBytes = freeBytes
        self.totalBytes = totalBytes
    }
}
