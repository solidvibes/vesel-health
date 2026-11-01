import Foundation

public struct SyncRun: Sendable, Equatable {
    public var id: Int64
    public var trigger: SyncTrigger
    public var startedAt: Date
    public var finishedAt: Date?
    public var outcome: SyncOutcome?
    public var detail: String?

    public init(id: Int64, trigger: SyncTrigger, startedAt: Date, finishedAt: Date?, outcome: SyncOutcome?, detail: String?) {
        self.id = id
        self.trigger = trigger
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.outcome = outcome
        self.detail = detail
    }
}

public enum SyncTrigger: String, Sendable, Codable {
    case launch, foreground, bandEvent, bandCheckIn, longRead, backgroundRefresh, shortcut, manual, imUp, paired
}

public enum SyncOutcome: String, Sendable, Codable {
    case success, partial, failed, unreachable
}

/// What `sync_run.detail` holds. Written by `BandSync`, read back only through `SyncRunWords`, never shown as it is.
/// The values equal what older versions stored, so older rows map too.
public enum SyncDetail {
    public static let notPaired = "No band paired"
    public static let notNearby = "Band not nearby"
    public static let didNotStart = "Band didn't start the sync"
    public static let stoppedEarly = "Stopped before it finished"
}
