import CryptoKit
import Foundation

/// What Vesel writes to Apple Health, one switch in Health's sheet per kind.
public enum HealthKind: String, CaseIterable, Sendable, Codable {
    case heartRate, restingHeartRate, respiratoryRate, sleep, steps

    /// As Loop & settings names it.
    public var name: String {
        switch self {
        case .heartRate: "Heart rate"
        case .restingHeartRate: "Resting heart rate"
        case .respiratoryRate: "Breathing rate"
        case .sleep: "Sleep"
        case .steps: "Steps"
        }
    }
}

/// What is written whole: a day (`heartRate/2026-11-03`, `steps/…`) or a night (`sleep/…`, `restingHeartRate/…`,
/// `respiratoryRate/…`). Its id is stored in Health on every sample (`VeselUnit`), so it never changes.
public struct HealthUnit: Hashable, Sendable {
    public var kind: HealthKind
    public var key: String

    public init(kind: HealthKind, key: String) {
        self.kind = kind
        self.key = key
    }

    public init(kind: HealthKind, day: DayKey) {
        self.init(kind: kind, key: day.description)
    }

    public init?(id: String) {
        guard let slash = id.firstIndex(of: "/"), let kind = HealthKind(rawValue: String(id[..<slash])) else { return nil }
        self.init(kind: kind, key: String(id[id.index(after: slash)...]))
    }

    public var id: String { "\(kind.rawValue)/\(key)" }

    /// The day or night it covers.
    public var day: DayKey? { DayKey(key) }
}

public enum HealthQuantityUnit: String, Sendable {
    case bpm, count, kcal, ms, breathsPerMinute
}

/// Apple's sleep stages that Vesel writes. Polar's unknown stretches have none: they're left out.
public enum HealthSleepValue: String, Sendable {
    case inBed, awake, core, deep, rem
}

/// One sample for Health, before HealthKit: the app's `HealthKitStore` turns it into an `HKSample`.
public struct HealthItem: Sendable, Equatable {
    public enum Value: Sendable, Equatable {
        case quantity(Double, HealthQuantityUnit)
        case sleep(HealthSleepValue)
    }

    public var kind: HealthKind
    public var start: Date
    public var end: Date
    public var value: Value
    /// Apple's sync identifier: a later save with the same id and a higher version replaces it.
    public var syncId: String

    public init(kind: HealthKind, start: Date, end: Date, value: Value, syncId: String) {
        self.kind = kind
        self.start = start
        self.end = end
        self.value = value
        self.syncId = syncId
    }

    /// One line that changes whenever anything written changes.
    var canonical: String {
        let value =
            switch self.value {
            case .quantity(let amount, let unit): "\(amount)\(unit.rawValue)"
            case .sleep(let stage): stage.rawValue
            }
        return "\(syncId)|\(kind.rawValue)|\(Self.milliseconds(start))|\(Self.milliseconds(end))|\(value)"
    }

    private static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}

/// A unit's items and their fingerprint. An empty batch removes what Vesel wrote for the unit before.
public struct HealthBatch: Sendable, Equatable {
    public var unit: HealthUnit
    public var items: [HealthItem]
    /// SHA-256 of the items and the kinds allowed (where a reading goes depends on them). The device isn't in it, so a
    /// firmware update doesn't rewrite history.
    public var digest: String

    public init(unit: HealthUnit, items: [HealthItem], allowed: Set<HealthKind>) {
        self.unit = unit
        self.items = items
        let kinds = allowed.map(\.rawValue).sorted().joined(separator: ",")
        let text = ([kinds] + items.map(\.canonical)).joined(separator: "\n")
        digest = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// How the last write to Health went, for Loop & settings. Stored as the setting `health.lastRun`.
public struct HealthRun: Sendable, Equatable, Codable {
    public enum Outcome: String, Sendable, Codable {
        /// Everything allowed was written, or `daysToGo` were left for the next run (time ran out).
        case written
        /// The phone was locked; the rest waits.
        case waitingForUnlock
        case failed
    }

    public var at: Date
    public var outcome: Outcome
    /// Days and nights still to write at the end of the run.
    public var daysToGo: Int
    /// Kinds the owner didn't allow in Health.
    public var notAllowed: [HealthKind]
    /// Whether anything has been written since the switch went on.
    public var wroteAny: Bool

    public init(at: Date, outcome: Outcome, daysToGo: Int, notAllowed: [HealthKind], wroteAny: Bool) {
        self.at = at
        self.outcome = outcome
        self.daysToGo = daysToGo
        self.notAllowed = notAllowed
        self.wroteAny = wroteAny
    }
}
