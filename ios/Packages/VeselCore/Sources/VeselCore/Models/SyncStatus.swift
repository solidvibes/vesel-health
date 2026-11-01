import Foundation

/// What the band sync is doing right now, as Today tells it.
public enum SyncStatus: Sendable, Equatable {
    case idle
    case reading(SyncProgress)
    /// A read is waiting for the Loop to come near.
    case waitingForLoop
    /// The last attempt couldn't reach the band. `lastRead` is the last time it was read all the way through.
    case unreachable(lastRead: Date?)

    public var isReading: Bool {
        if case .reading = self { return true }
        return false
    }
}

/// Which parts of a read are in, for Today's reading list. Counts only, never health values.
public struct SyncProgress: Sendable, Equatable {
    public var loopFound: Bool
    public var heartRate: Bool
    /// Of sleep, Nightly Recharge and skin temperature.
    public var nightParts: Int
    /// 3 when the band has stopped recording sleep, so the night is read; 0 otherwise (the row is left out).
    public var nightPartsTotal: Int
    /// Worked out after the band is read, not fetched.
    public var stressToday: Bool

    static let nightKinds: [FetchKind] = [.sleep, .nightlyRecharge, .skinTemperature]

    public init(loopFound: Bool = false, heartRate: Bool = false, nightParts: Int = 0, nightPartsTotal: Int = 0, stressToday: Bool = false) {
        self.loopFound = loopFound
        self.heartRate = heartRate
        self.nightParts = nightParts
        self.nightPartsTotal = nightPartsTotal
        self.stressToday = stressToday
    }

    public func applying(_ step: SyncStep) -> SyncProgress {
        var next = self
        switch step {
        case .waitingForLoop:
            break
        case .loopFound:
            next.loopFound = true
        case .kinds(let kinds):
            next.nightPartsTotal = kinds.contains(.sleep) ? Self.nightKinds.count : 0
        case .fetched(let kind):
            if kind == .heartRate { next.heartRate = true }
            if nightPartsTotal > 0, Self.nightKinds.contains(kind) { next.nightParts += 1 }
        }
        return next
    }
}

/// What `BandSync` reports as a read goes: it waits for the Loop (only when it wasn't connected), the Loop answered, the
/// kinds it will fetch, then each kind as it comes in.
public enum SyncStep: Sendable, Equatable {
    case waitingForLoop
    case loopFound
    case kinds([FetchKind])
    case fetched(FetchKind)
}
