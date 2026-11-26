import CoreLocation
import Foundation
import HealthKit
import VeselCore
import VeselStorage
import VeselSync

/// The only code that touches HealthKit. Share-only: it never asks to read, and queries nothing but Vesel's own samples, to
/// remove the older copies of a unit. Never logs a value or a sample. A workout's route is built from its stored points; the
/// phone's location is never asked for or read here.
final class HealthKitStore: HealthStore {
    /// The metadata key that ties each sample to what it was written for (`HealthUnit.id`).
    static let unitKey = "VeselUnit"

    /// False on a device without Health (an iPad): Loop & settings hides the section.
    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private let store = HKHealthStore()
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    /// Every type a kind is saved as (and removed from). A workout's route is optional: without it, workouts go without routes.
    static func types(_ kind: HealthKind) -> [HKSampleType] {
        switch kind {
        case .heartRate: [HKQuantityType(.heartRate)]
        case .restingHeartRate: [HKQuantityType(.restingHeartRate)]
        case .respiratoryRate: [HKQuantityType(.respiratoryRate)]
        case .sleep: [HKCategoryType(.sleepAnalysis)]
        case .steps: [HKQuantityType(.stepCount)]
        case .hrv: [HKQuantityType(.heartRateVariabilitySDNN)]
        case .energy: [HKQuantityType(.activeEnergyBurned), HKQuantityType(.basalEnergyBurned)]
        case .workout: [HKWorkoutType.workoutType(), HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned), HKSeriesType.workoutRoute()]
        }
    }

    private static let routeType = HKSeriesType.workoutRoute()

    func authorization() async -> [HealthKind: HealthAccess] {
        Dictionary(
            uniqueKeysWithValues: HealthKind.allCases.map { kind in
                let types = Self.types(kind)
                if types.map(store.authorizationStatus(for:)).contains(.notDetermined) { return (kind, .notAsked) }
                let required = types.filter { $0 != Self.routeType }.map(store.authorizationStatus(for:))
                return (kind, required.contains(.sharingDenied) ? .denied : .allowed)
            })
    }

    func requestAuthorization() async throws {
        do {
            try await store.requestAuthorization(toShare: Set(HealthKind.allCases.flatMap(Self.types)), read: [])
        } catch {
            throw Self.storeError(error)
        }
    }

    func save(_ items: [HealthItem], unit: HealthUnit, version: Int64) async throws {
        let device = Self.device(firmware: try? await database.band()?.firmware)
        do {
            let samples = items.compactMap { item -> HKSample? in
                if case .workout = item.value { return nil }
                return Self.sample(item, unit: unit, version: version, device: device)
            }
            if !samples.isEmpty { try await store.save(samples) }
            for item in items {
                if case .workout(let workout) = item.value {
                    try await save(item, workout: workout, unit: unit, version: version, device: device)
                }
            }
        } catch let error as HealthStoreError {
            throw error
        } catch {
            throw Self.storeError(error)
        }
    }

    /// The workout with its energy and heart rate, then its route when Health allows routes. Every object carries the
    /// sync id, version and unit, so a rewrite replaces it and the stale removal finds the old ones.
    private func save(_ item: HealthItem, workout: HealthWorkout, unit: HealthUnit, version: Int64, device: HKDevice) async throws {
        let builder = HKWorkoutBuilder(healthStore: store, configuration: Self.configuration(workout.activity), device: device)
        try await builder.beginCollection(at: item.start)
        let samples = workout.samples.map { Self.sample($0, unit: unit, version: version, device: device) }
        if !samples.isEmpty { try await builder.addSamples(samples) }
        try await builder.addMetadata(Self.metadata(syncId: item.syncId, unit: unit, version: version))
        try await builder.endCollection(at: item.end)
        guard let saved = try await builder.finishWorkout() else { throw HealthStoreError.failed }
        guard !workout.route.isEmpty, store.authorizationStatus(for: Self.routeType) == .sharingAuthorized else { return }
        let route = HKWorkoutRouteBuilder(healthStore: store, device: device)
        try await route.insertRouteData(Self.locations(workout.route))
        try await route.finishRoute(with: saved, metadata: Self.metadata(syncId: "\(item.syncId).route", unit: unit, version: version))
    }

    static func configuration(_ activity: HealthWorkoutActivity) -> HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType =
            switch activity {
            case .running: .running
            case .cycling: .cycling
            case .swimming: .swimming
            case .strength: .traditionalStrengthTraining
            case .other: .other
            }
        return configuration
    }

    /// Stored route points as locations, with their time and accuracy; no altitude.
    static func locations(_ points: [RoutePoint]) -> [CLLocation] {
        points.map { point in
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude), altitude: 0,
                horizontalAccuracy: point.accuracy, verticalAccuracy: -1, timestamp: point.time)
        }
    }

    func removeStale(unit: HealthUnit, kind: HealthKind, below version: Int64) async throws {
        let predicate = Self.stalePredicate(unit: unit, below: version)
        do {
            for type in Self.types(kind) {
                _ = try await store.deleteObjects(of: type, predicate: predicate)
            }
        } catch {
            throw Self.storeError(error)
        }
    }

    /// Only Vesel's own objects, only of this unit, only older than `version`.
    static func stalePredicate(unit: HealthUnit, below version: Int64) -> NSPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(from: HKSource.default()),
            HKQuery.predicateForObjects(withMetadataKey: unitKey, allowedValues: [unit.id]),
            HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncVersion, operatorType: .lessThan, value: NSNumber(value: version)),
        ])
    }

    static func device(firmware: String?) -> HKDevice {
        HKDevice(
            name: "Polar Loop", manufacturer: "Polar Electro", model: "Loop", hardwareVersion: nil, firmwareVersion: firmware, softwareVersion: nil,
            localIdentifier: nil, udiDeviceIdentifier: nil)
    }

    static func metadata(syncId: String, unit: HealthUnit, version: Int64) -> [String: Any] {
        [HKMetadataKeySyncIdentifier: syncId, HKMetadataKeySyncVersion: NSNumber(value: version), unitKey: unit.id]
    }

    /// A quantity or sleep sample. Workouts are built by `save`, never here.
    static func sample(_ item: HealthItem, unit: HealthUnit, version: Int64, device: HKDevice) -> HKSample {
        let metadata = metadata(syncId: item.syncId, unit: unit, version: version)
        switch item.value {
        case .quantity(let amount, let quantityUnit):
            return HKQuantitySample(
                type: quantityType(item.type), quantity: HKQuantity(unit: hkUnit(quantityUnit), doubleValue: amount), start: item.start, end: item.end,
                device: device, metadata: metadata)
        case .sleep(let stage):
            return HKCategorySample(
                type: HKCategoryType(.sleepAnalysis), value: sleepValue(stage).rawValue, start: item.start, end: item.end, device: device,
                metadata: metadata)
        case .workout:
            preconditionFailure("A workout is built, not a sample")
        }
    }

    private static func quantityType(_ type: HealthType) -> HKQuantityType {
        switch type {
        case .heartRate: HKQuantityType(.heartRate)
        case .restingHeartRate: HKQuantityType(.restingHeartRate)
        case .respiratoryRate: HKQuantityType(.respiratoryRate)
        case .steps: HKQuantityType(.stepCount)
        case .hrv: HKQuantityType(.heartRateVariabilitySDNN)
        case .activeEnergy: HKQuantityType(.activeEnergyBurned)
        case .restingEnergy: HKQuantityType(.basalEnergyBurned)
        case .sleep, .workout: preconditionFailure("Not a quantity")
        }
    }

    static func hkUnit(_ unit: HealthQuantityUnit) -> HKUnit {
        switch unit {
        case .bpm, .breathsPerMinute: .count().unitDivided(by: .minute())
        case .count: .count()
        case .kcal: .kilocalorie()
        case .ms: .secondUnit(with: .milli)
        }
    }

    private static func sleepValue(_ stage: HealthSleepValue) -> HKCategoryValueSleepAnalysis {
        switch stage {
        case .inBed: .inBed
        case .awake: .awake
        case .core: .asleepCore
        case .deep: .asleepDeep
        case .rem: .asleepREM
        }
    }

    /// Locked: Health's database can't be used until the phone is unlocked. Never carries the error's text on.
    static func storeError(_ error: any Error) -> HealthStoreError {
        switch (error as? HKError)?.code {
        case .errorDatabaseInaccessible?: .locked
        case .errorAuthorizationDenied?, .errorAuthorizationNotDetermined?: .notAllowed
        default: .failed
        }
    }
}
