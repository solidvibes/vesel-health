import Foundation

/// One day of one fetch kind in `band_ledger`: when it was stored on the phone, and when it was cleared off the band.
public struct LedgerEntry: Sendable, Equatable {
    public var day: DayKey
    public var kind: FetchKind
    public var storedAt: Date
    public var sampleCount: Int
    public var deletedFromBandAt: Date?
    /// For a day that read empty: when it also read empty on the sync before (nil if that read wasn't empty, or there was none).
    public var earlierEmptyAt: Date?

    public init(day: DayKey, kind: FetchKind, storedAt: Date, sampleCount: Int, deletedFromBandAt: Date?, earlierEmptyAt: Date? = nil) {
        self.day = day
        self.kind = kind
        self.storedAt = storedAt
        self.sampleCount = sampleCount
        self.deletedFromBandAt = deletedFromBandAt
        self.earlierEmptyAt = earlierEmptyAt
    }
}
