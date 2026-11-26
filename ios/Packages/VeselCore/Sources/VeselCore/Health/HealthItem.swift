import CryptoKit
import Foundation

/// What Vesel writes to Apple Health, one switch in Health's sheet per kind.
public enum HealthKind: String, CaseIterable, Sendable, Codable {
    case heartRate, restingHeartRate, respiratoryRate, sleep, steps, hrv, energy, workout

    /// As Loop & settings names it.
    public var name: String {
        switch self {
        case .heartRate: "Heart rate"
        case .restingHeartRate: "Resting heart rate"
        case .respiratoryRate: "Breathing rate"
        case .sleep: "Sleep"
        case .steps: "Steps"
        case .hrv: "HRV"
        case .energy: "Energy"
        case .workout: "Workouts"
        }
    }
}

/// The Health type a sample is saved as. Energy is two types; a workout's heart rate and energy are saved with it.
public enum HealthType: String, Sendable {
    case heartRate, restingHeartRate, respiratoryRate, sleep, steps, hrv, activeEnergy, restingEnergy, workout
}

/// What is written whole: a day (`heartRate/2026-11-03`, `steps/…`, `energy/…`), a night (`sleep/…`, `restingHeartRate/…`,
/// `respiratoryRate/…`, `hrv/…`) or a workout (`workout/20261103/071000`). Its id is stored in Health on every sample
/// (`VeselUnit`), so it never changes.
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

    /// The day or night it covers; nil for a workout.
    public var day: DayKey? { DayKey(key) }

    /// For newest first: the day, or the day a workout's session folder names.
    public var date: String {
        guard kind == .workout, key.count >= 8 else { return key }
        let digits = Array(key.prefix(8))
        return "\(String(digits[0..<4]))-\(String(digits[4..<6]))-\(String(digits[6..<8]))"
    }
}

public enum HealthQuantityUnit: String, Sendable {
    case bpm, count, kcal, ms, breathsPerMinute
}

/// Apple's sleep stages that Vesel writes. Polar's unknown stretches have none: they're left out.
public enum HealthSleepValue: String, Sendable {
    case inBed, awake, core, deep, rem
}

/// A workout's sport in Health. Only the Loop's or the owner's sport is written; Vesel's guesses are `other`.
public enum HealthWorkoutActivity: String, Sendable {
    case running, cycling, swimming, strength, other
}

/// A workout for Health: its sport, the active energy and heart rate saved with it, and its route from stored points.
public struct HealthWorkout: Sendable, Equatable {
    public var activity: HealthWorkoutActivity
    public var samples: [HealthItem]
    /// Cut to the workout, exact to 25 m; empty without a route.
    public var route: [RoutePoint]

    public init(activity: HealthWorkoutActivity, samples: [HealthItem], route: [RoutePoint]) {
        self.activity = activity
        self.samples = samples
        self.route = route
    }
}

/// One sample for Health, before HealthKit: the app's `HealthKitStore` turns it into an `HKSample` or a workout.
public struct HealthItem: Sendable, Equatable {
    public enum Value: Sendable, Equatable {
        case quantity(Double, HealthQuantityUnit)
        case sleep(HealthSleepValue)
        case workout(HealthWorkout)
    }

    public var type: HealthType
    public var start: Date
    public var end: Date
    public var value: Value
    /// Apple's sync identifier: a later save with the same id and a higher version replaces it.
    public var syncId: String

    public init(type: HealthType, start: Date, end: Date, value: Value, syncId: String) {
        self.type = type
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
            case .workout(let workout):
                ([workout.activity.rawValue] + workout.samples.map(\.canonical)
                    + workout.route.map { "\(Self.milliseconds($0.time)),\($0.latitude),\($0.longitude),\($0.accuracy)" })
                    .joined(separator: ";")
            }
        return "\(syncId)|\(type.rawValue)|\(Self.milliseconds(start))|\(Self.milliseconds(end))|\(value)"
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
