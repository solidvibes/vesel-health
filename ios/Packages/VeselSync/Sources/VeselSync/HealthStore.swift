import VeselCore

/// Whether the owner let Vesel write a kind, as Apple's Health sheet left it.
public enum HealthAccess: Sendable, Equatable {
    /// Every type of the kind is allowed.
    case allowed
    /// At least one type was turned off in Health.
    case denied
    /// At least one type was never in a sheet the owner answered (a newer Vesel writes it).
    case notAsked
}

public enum HealthStoreError: Error, Equatable {
    /// The phone is locked: Health can't be queried or have samples deleted until it is unlocked.
    case locked
    case notAllowed
    case failed
}

/// Apple Health as the writer sees it. The app's `HealthKitStore` is the only implementation that touches HealthKit; it never
/// reads anything but Vesel's own samples, and only to remove them.
public protocol HealthStore: Sendable {
    func authorization() async -> [HealthKind: HealthAccess]
    /// Apple's sheet, for every type Vesel writes; it shows only those not asked yet. Share only, never read.
    func requestAuthorization() async throws
    /// Saves each item with its sync id, `version` and the unit's id.
    func save(_ items: [HealthItem], unit: HealthUnit, version: Int64) async throws
    /// Deletes Vesel's own objects of `kind`'s types for `unit` with a sync version below `version`, and nothing else.
    func removeStale(unit: HealthUnit, kind: HealthKind, below version: Int64) async throws
}
