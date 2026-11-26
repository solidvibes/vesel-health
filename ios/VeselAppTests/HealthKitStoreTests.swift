import CoreLocation
import Foundation
import HealthKit
import Testing
import VeselCore
import VeselSync
@testable import Vesel

/// What each item becomes in HealthKit, and what HealthKit's errors mean to the writer. Nothing is saved to Health here.
struct HealthKitStoreTests {
    let start = try! Date("2026-10-27T09:00:00Z", strategy: .iso8601)
    let unit = HealthUnit(kind: .heartRate, key: "2026-10-27")

    func sample(_ type: HealthType, _ value: HealthItem.Value) -> HKSample {
        HealthKitStore.sample(
            HealthItem(type: type, start: start, end: start.addingTimeInterval(60), value: value, syncId: "vesel.test"),
            unit: unit, version: 1_793_091_600_000, device: HealthKitStore.device(firmware: "2.1.0"))
    }

    @Test func quantitiesGoToTheirTypeInTheirUnit() throws {
        let cases: [(HealthType, HealthItem.Value, HKQuantityTypeIdentifier, HKUnit, Double)] = [
            (.heartRate, .quantity(61, .bpm), .heartRate, .count().unitDivided(by: .minute()), 61),
            (.restingHeartRate, .quantity(52.5, .bpm), .restingHeartRate, .count().unitDivided(by: .minute()), 52.5),
            (.respiratoryRate, .quantity(14.2, .breathsPerMinute), .respiratoryRate, .count().unitDivided(by: .minute()), 14.2),
            (.steps, .quantity(420, .count), .stepCount, .count(), 420),
            (.hrv, .quantity(41.5, .ms), .heartRateVariabilitySDNN, .secondUnit(with: .milli), 41.5),
            (.activeEnergy, .quantity(336, .kcal), .activeEnergyBurned, .kilocalorie(), 336),
            (.restingEnergy, .quantity(1728, .kcal), .basalEnergyBurned, .kilocalorie(), 1728),
        ]
        for (type, value, identifier, hkUnit, amount) in cases {
            let quantity = try #require(sample(type, value) as? HKQuantitySample)
            #expect(quantity.quantityType == HKQuantityType(identifier))
            #expect(quantity.quantity.doubleValue(for: hkUnit) == amount)
            #expect(quantity.startDate == start)
        }
    }

    @Test func sleepStagesAreApplesSleepValues() throws {
        let stages: [(HealthSleepValue, HKCategoryValueSleepAnalysis)] = [
            (.inBed, .inBed), (.awake, .awake), (.core, .asleepCore), (.deep, .asleepDeep), (.rem, .asleepREM),
        ]
        for (stage, expected) in stages {
            let category = try #require(sample(.sleep, .sleep(stage)) as? HKCategorySample)
            #expect(category.categoryType == HKCategoryType(.sleepAnalysis))
            #expect(category.value == expected.rawValue)
        }
    }

    @Test func everySampleCarriesItsIdVersionUnitAndTheLoop() {
        let written = sample(.heartRate, .quantity(61, .bpm))

        #expect(written.metadata?[HKMetadataKeySyncIdentifier] as? String == "vesel.test")
        #expect((written.metadata?[HKMetadataKeySyncVersion] as? NSNumber)?.int64Value == 1_793_091_600_000)
        #expect(written.metadata?[HealthKitStore.unitKey] as? String == "heartRate/2026-10-27")
        #expect(written.device?.name == "Polar Loop")
        #expect(written.device?.manufacturer == "Polar Electro")
        #expect(written.device?.model == "Loop")
        #expect(written.device?.firmwareVersion == "2.1.0")
    }

    @Test func aLockedPhoneAndARefusalAreToldApart() {
        #expect(HealthKitStore.storeError(HKError(.errorDatabaseInaccessible)) == .locked)
        #expect(HealthKitStore.storeError(HKError(.errorAuthorizationDenied)) == .notAllowed)
        #expect(HealthKitStore.storeError(HKError(.errorAuthorizationNotDetermined)) == .notAllowed)
        #expect(HealthKitStore.storeError(HKError(.errorInvalidArgument)) == .failed)
        #expect(HealthKitStore.storeError(CocoaError(.fileNoSuchFile)) == .failed)
    }

    /// Removal never reaches past Vesel's own samples of the unit below the version.
    @Test func theStaleRemovalIsOwnUnitAndOlderVersionOnly() {
        let predicate = HealthKitStore.stalePredicate(unit: unit, below: 5) as? NSCompoundPredicate

        #expect(predicate?.compoundPredicateType == .and)
        #expect(predicate?.subpredicates.count == 3)
        #expect(predicate?.predicateFormat.contains("heartRate/2026-10-27") == true)
    }

    @Test func aWorkoutIsItsSportOrOther() {
        let activities: [(HealthWorkoutActivity, HKWorkoutActivityType)] = [
            (.running, .running), (.cycling, .cycling), (.swimming, .swimming), (.strength, .traditionalStrengthTraining), (.other, .other),
        ]
        for (activity, expected) in activities {
            #expect(HealthKitStore.configuration(activity).activityType == expected)
        }
    }

    /// A route is the stored points, with their time and accuracy and no altitude.
    @Test func aRouteIsTheStoredPoints() throws {
        let point = RoutePoint(time: start, latitude: 52.52, longitude: 13.405, accuracy: 8)

        let location = try #require(HealthKitStore.locations([point]).first)

        #expect(location.coordinate.latitude == 52.52)
        #expect(location.coordinate.longitude == 13.405)
        #expect(location.horizontalAccuracy == 8)
        #expect(location.verticalAccuracy < 0)
        #expect(location.timestamp == start)
    }

    /// A workout kind takes the workout, heart rate, active energy and route types; energy takes active and resting.
    @Test func eachKindNamesItsTypes() {
        #expect(HealthKitStore.types(.workout) == [HKWorkoutType.workoutType(), HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned), HKSeriesType.workoutRoute()])
        #expect(HealthKitStore.types(.energy) == [HKQuantityType(.activeEnergyBurned), HKQuantityType(.basalEnergyBurned)])
        #expect(HealthKitStore.types(.hrv) == [HKQuantityType(.heartRateVariabilitySDNN)])
    }
}
