import Foundation
import GRDB
import VeselCore

/// Everything any widget shows, read in one go. Widget code never works anything out: VeselStorage fills this from stored numbers.
public struct WidgetSnapshot: Sendable, Equatable {
    public enum Content: Sendable, Equatable {
        /// No night stored yet, no database yet, or one the app has not brought to this version.
        case noData
        /// Fewer than 7 earlier nights: Polar's numbers show, with "Learning your normal".
        case learning(nights: Int)
        case ready
    }

    /// A snapshot older than this is shown dimmed, with the time it is from.
    public static let staleAfter: TimeInterval = 12 * 3600

    public var night: DayKey?
    public var status: RecoveryStatus?
    public var asleepMinutes: Double?
    public var lines: DayLines
    public var headline: Headline?
    public var stressNow: StressNow?
    public var stressDays: Int
    public var earlierNights: Int
    /// When the band was last read all the way through.
    public var syncedAt: Date?
    public var units: Units

    public static let empty = WidgetSnapshot(stressDays: 0, earlierNights: 0)

    public init(
        night: DayKey? = nil, status: RecoveryStatus? = nil, asleepMinutes: Double? = nil, lines: DayLines = .empty,
        headline: Headline? = nil, stressNow: StressNow? = nil, stressDays: Int,
        earlierNights: Int, syncedAt: Date? = nil, units: Units = .metric
    ) {
        self.night = night
        self.status = status
        self.asleepMinutes = asleepMinutes
        self.lines = lines
        self.headline = headline
        self.stressNow = stressNow
        self.stressDays = stressDays
        self.earlierNights = earlierNights
        self.syncedAt = syncedAt
        self.units = units
    }

    public var content: Content {
        guard night != nil else { return .noData }
        return earlierNights < PersonalRange.minimumNights ? .learning(nights: earlierNights) : .ready
    }

    /// `now` is the timeline entry's date, never the clock.
    public func isStale(at now: Date) -> Bool {
        syncedAt.map { now.timeIntervalSince($0) > Self.staleAfter } ?? false
    }

    public func stress(at now: Date) -> StressGlance {
        StressGlance(days: stressDays, now: stressNow, at: now)
    }
}

extension AppDatabase {
    /// One read for every widget. Opens the shared database read-only, reads, and closes it; never migrates, never
    /// writes. `.empty` when there is no database yet or the app has not brought it to this version (a newer or
    /// older schema); throws only when the file could not be read.
    #if os(iOS)
    public static func readSnapshot(today: DayKey) throws -> WidgetSnapshot {
        guard let appGroup, let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            return .empty
        }
        return try readSnapshot(in: container.appending(path: "Library/Application Support/Vesel", directoryHint: .isDirectory), today: today)
    }
    #endif

    static func readSnapshot(in directory: URL, today: DayKey) throws -> WidgetSnapshot {
        let url = directory.appending(path: "vesel.sqlite")
        guard FileManager.default.fileExists(atPath: url.path) else { return .empty }
        var configuration = Configuration()
        configuration.readonly = true
        configuration.busyMode = .timeout(2)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinatorError: NSError?
        var result: Result<WidgetSnapshot, any Error>?
        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinatorError) { url in
            result = Result {
                let queue = try DatabaseQueue(path: url.path, configuration: configuration)
                defer { try? queue.close() }
                return try queue.read { db in
                    guard try migrator.hasCompletedMigrations(db), !(try migrator.hasBeenSuperseded(db)) else { return .empty }
                    return try widgetSnapshot(db, today: today)
                }
            }
        }
        if let coordinatorError { throw coordinatorError }
        guard let result else { throw StorageError.notOpened }
        return try result.get()
    }

    static func widgetSnapshot(_ db: Database, today: DayKey) throws -> WidgetSnapshot {
        let snapshot = try todaySnapshot(db, day: today, today: today)
        let syncedAt = try lastSuccessfulSync(db)
        let units = try Self.units(db)
        let asleep = snapshot.latest?.value(MetricKind.sleepAsleep)
        let headline = Headline.make(
            lines: snapshot.lines, status: snapshot.latest?.status, contributors: snapshot.latest?.contributors ?? [], asleepMinutes: asleep, units: units
        )
        guard let latest = snapshot.latest else {
            return WidgetSnapshot(
                lines: snapshot.lines, headline: headline, stressNow: snapshot.stressNow, stressDays: snapshot.stressDays, earlierNights: 0,
                syncedAt: syncedAt, units: units
            )
        }
        return WidgetSnapshot(
            night: latest.night,
            status: latest.status,
            asleepMinutes: asleep,
            lines: snapshot.lines,
            headline: headline,
            stressNow: snapshot.stressNow,
            stressDays: snapshot.stressDays,
            earlierNights: snapshot.earlierNights,
            syncedAt: syncedAt,
            units: units
        )
    }
}
