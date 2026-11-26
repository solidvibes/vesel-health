import Foundation
import HealthKit
import VeselCore
import VeselStorage
import VeselSync

/// The only code that touches HealthKit. Share-only: it never asks to read, and queries nothing but Vesel's own samples, to
/// remove the older copies of a unit. Never logs a value or a sample.
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

    static func types(_ kind: HealthKind) -> [HKSampleType] {
        switch kind {
        case .heartRate: [HKQuantityType(.heartRate)]
        case .restingHeartRate: [HKQuantityType(.restingHeartRate)]
        case .respiratoryRate: [HKQuantityType(.respiratoryRate)]
        case .sleep: [HKCategoryType(.sleepAnalysis)]
        case .steps: [HKQuantityType(.stepCount)]
        }
    }

    func authorization() async -> [HealthKind: HealthAccess] {
        Dictionary(
            uniqueKeysWithValues: HealthKind.allCases.map { kind in
                let statuses = Self.types(kind).map(store.authorizationStatus(for:))
                if statuses.contains(.notDetermined) { return (kind, .notAsked) }
                return (kind, statuses.contains(.sharingDenied) ? .denied : .allowed)
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
            try await store.save(items.map { Self.sample($0, unit: unit, version: version, device: device) })
        } catch {
            throw Self.storeError(error)
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

    static func sample(_ item: HealthItem, unit: HealthUnit, version: Int64, device: HKDevice) -> HKSample {
        let metadata: [String: Any] = [
            HKMetadataKeySyncIdentifier: item.syncId,
            HKMetadataKeySyncVersion: NSNumber(value: version),
            unitKey: unit.id,
        ]
        switch item.value {
        case .quantity(let amount, let quantityUnit):
            return HKQuantitySample(
                type: quantityType(item.kind), quantity: HKQuantity(unit: hkUnit(quantityUnit), doubleValue: amount), start: item.start, end: item.end,
                device: device, metadata: metadata)
        case .sleep(let stage):
            return HKCategorySample(
                type: HKCategoryType(.sleepAnalysis), value: sleepValue(stage).rawValue, start: item.start, end: item.end, device: device,
                metadata: metadata)
        }
    }

    private static func quantityType(_ kind: HealthKind) -> HKQuantityType {
        switch kind {
        case .heartRate: HKQuantityType(.heartRate)
        case .restingHeartRate: HKQuantityType(.restingHeartRate)
        case .respiratoryRate: HKQuantityType(.respiratoryRate)
        case .steps: HKQuantityType(.stepCount)
        case .sleep: preconditionFailure("Sleep is a category")
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
