import Foundation
import Testing
@testable import VeselCore

struct HealthMappingTests {
    /// The sample night's ten phases become ten pieces after "In bed", light as core, at their own times.
    @Test func sleepIsInBedThenEachStageAsAPiece() {
        let items = HealthMapping.sleep(sampleNight())

        #expect(items.first == HealthItem(type: .sleep, start: at("2026-10-25T21:30:00Z"), end: at("2026-10-26T05:30:00Z"), value: .sleep(.inBed), syncId: "vesel.sleep.2026-10-26.inBed"))
        let pieces = items.dropFirst().map { "\($0.start.formatted(.iso8601))–\($0.end.formatted(.iso8601)) \($0.value)" }
        #expect(
            pieces == [
                "2026-10-25T21:30:00Z–2026-10-25T22:00:00Z sleep(VeselCore.HealthSleepValue.core)",
                "2026-10-25T22:00:00Z–2026-10-25T23:00:00Z sleep(VeselCore.HealthSleepValue.deep)",
                "2026-10-25T23:00:00Z–2026-10-25T23:30:00Z sleep(VeselCore.HealthSleepValue.core)",
                "2026-10-25T23:30:00Z–2026-10-26T00:00:00Z sleep(VeselCore.HealthSleepValue.rem)",
                "2026-10-26T00:00:00Z–2026-10-26T00:10:00Z sleep(VeselCore.HealthSleepValue.awake)",
                "2026-10-26T00:10:00Z–2026-10-26T01:30:00Z sleep(VeselCore.HealthSleepValue.core)",
                "2026-10-26T01:30:00Z–2026-10-26T02:30:00Z sleep(VeselCore.HealthSleepValue.deep)",
                "2026-10-26T02:30:00Z–2026-10-26T03:30:00Z sleep(VeselCore.HealthSleepValue.rem)",
                "2026-10-26T03:30:00Z–2026-10-26T05:20:00Z sleep(VeselCore.HealthSleepValue.core)",
                "2026-10-26T05:20:00Z–2026-10-26T05:30:00Z sleep(VeselCore.HealthSleepValue.awake)",
            ])
        #expect(items[1].syncId == "vesel.sleep.2026-10-26.\(Int64(at("2026-10-25T21:30:00Z").timeIntervalSince1970))")
    }

    /// Before the first phase is awake; equal phases in a row are one piece; unknown is left out.
    @Test func sleepMergesRunsAndLeavesOutUnknown() {
        let night = SleepNight(
            night: day("2026-10-26"), start: at("2026-10-25T22:00:00Z"), end: at("2026-10-26T02:00:00Z"), goalMinutes: nil,
            phases: [
                SleepPhase(secondsFromStart: 600, state: .light), SleepPhase(secondsFromStart: 1800, state: .light),
                SleepPhase(secondsFromStart: 3600, state: .unknown), SleepPhase(secondsFromStart: 7200, state: .deep),
            ])

        let pieces = HealthMapping.sleep(night).dropFirst().map { ($0.start, $0.end, $0.value) }

        #expect(pieces.count == 3)
        #expect(pieces[0] == (at("2026-10-25T22:00:00Z"), at("2026-10-25T22:10:00Z"), .sleep(.awake)))
        #expect(pieces[1] == (at("2026-10-25T22:10:00Z"), at("2026-10-25T23:00:00Z"), .sleep(.core)))
        #expect(pieces[2] == (at("2026-10-26T00:00:00Z"), at("2026-10-26T02:00:00Z"), .sleep(.deep)))
    }

    @Test func stepsAreSummedPerRealHourWithTheCurrentHourEndingAtItsLastMinute() {
        let samples: [HourlySteps.Sample] = [
            .init(time: "2026-10-26T07:59:00+01:00", steps: 10),
            .init(time: "2026-10-26T08:00:00+01:00", steps: 20),
            .init(time: "2026-10-26T08:30:00+01:00", steps: 15),
            .init(time: "2026-10-26T09:00:00+01:00", steps: 0),
            .init(time: "2026-10-26T14:01:00+01:00", steps: 40),
            .init(time: "2026-10-27T00:10:00+01:00", steps: 99),
        ]

        let items = HealthMapping.steps(day: day("2026-10-26"), samples: samples)

        #expect(items.map(\.value) == [.quantity(10, .count), .quantity(35, .count), .quantity(40, .count)])
        #expect(items.map(\.start) == [at("2026-10-26T06:00:00Z"), at("2026-10-26T07:00:00Z"), at("2026-10-26T13:00:00Z")])
        #expect(items.map(\.end) == [at("2026-10-26T07:00:00Z"), at("2026-10-26T07:31:00Z"), at("2026-10-26T13:02:00Z")])
        #expect(items[0].syncId == "vesel.steps.\(Int64(at("2026-10-26T06:00:00Z").timeIntervalSince1970))")
    }

    /// 01:00–02:00 happens twice on 25 October in Berlin: two hours, an hour apart.
    @Test func theHourThatRepeatsWhenClocksGoBackIsTwoHours() {
        let samples: [HourlySteps.Sample] = [
            .init(time: "2026-10-25T01:30:00+02:00", steps: 30),
            .init(time: "2026-10-25T01:30:00+01:00", steps: 20),
            .init(time: "2026-10-25T02:10:00+01:00", steps: 7),
        ]

        let items = HealthMapping.steps(day: day("2026-10-25"), samples: samples)

        #expect(items.map(\.start) == [at("2026-10-24T23:00:00Z"), at("2026-10-25T00:00:00Z"), at("2026-10-25T01:00:00Z")])
        #expect(items.map(\.value) == [.quantity(30, .count), .quantity(20, .count), .quantity(7, .count)])
        #expect(Set(items.map(\.syncId)).count == 3)
    }

    @Test func restingHeartRateAndBreathingSpanTheSleepWindow() {
        let night = sampleNight()

        let resting = HealthMapping.restingHeartRate(night: night.night, bpm: 52.5, sleep: night, utcOffsetSeconds: 3600)
        let breathing = HealthMapping.respiratoryRate(night: night.night, breathsPerMinute: 14.2, sleep: night, utcOffsetSeconds: 3600)

        #expect(resting == HealthItem(type: .restingHeartRate, start: night.start, end: night.end, value: .quantity(52.5, .bpm), syncId: "vesel.restingHR.2026-10-26"))
        #expect(breathing == HealthItem(type: .respiratoryRate, start: night.start, end: night.end, value: .quantity(14.2, .breathsPerMinute), syncId: "vesel.breathing.2026-10-26"))
    }

    /// No sleep row: the night's day, midnight to midnight in the Nightly Recharge's offset (UTC+1).
    @Test func withoutSleepTheyCoverTheNightsDay() {
        let resting = HealthMapping.restingHeartRate(night: day("2026-10-26"), bpm: 52, sleep: nil, utcOffsetSeconds: 3600)

        #expect(resting.start == at("2026-10-25T23:00:00Z"))
        #expect(resting.end == at("2026-10-26T23:00:00Z"))
    }

    @Test func eachReadingIsAHeartRateSampleAtItsTime() {
        let items = HealthMapping.heartRate([HeartRateSample(time: at("2026-10-26T09:00:00Z"), bpm: 61, trigger: .timed)])

        #expect(items == [HealthItem(type: .heartRate, start: at("2026-10-26T09:00:00Z"), end: at("2026-10-26T09:00:00Z"), value: .quantity(61, .bpm), syncId: "vesel.hr.1793005200")])
    }

    /// The same items give the same fingerprint; a changed value or another set of allowed kinds don't.
    @Test func theFingerprintFollowsTheItemsAndTheAllowedKinds() {
        let unit = HealthUnit(kind: .heartRate, day: day("2026-10-26"))
        let items = HealthMapping.heartRate([HeartRateSample(time: at("2026-10-26T09:00:00Z"), bpm: 61, trigger: .timed)])
        let changed = HealthMapping.heartRate([HeartRateSample(time: at("2026-10-26T09:00:00Z"), bpm: 62, trigger: .timed)])
        let all = Set(HealthKind.allCases)

        let digest = HealthBatch(unit: unit, items: items, allowed: all).digest
        #expect(HealthBatch(unit: unit, items: items, allowed: all).digest == digest)
        #expect(HealthBatch(unit: unit, items: changed, allowed: all).digest != digest)
        #expect(HealthBatch(unit: unit, items: items, allowed: [.heartRate]).digest != digest)
        #expect(digest.count == 64)
    }

    @Test func aUnitIdReadsBack() {
        let unit = HealthUnit(kind: .restingHeartRate, day: day("2026-10-26"))
        #expect(unit.id == "restingHeartRate/2026-10-26")
        #expect(HealthUnit(id: unit.id) == unit)
        #expect(unit.day == day("2026-10-26"))
    }

    /// 07:10 in Berlin on 3 November, 42 minutes, 500 kcal.
    func workout(calories: Int? = 500, heartRates: WorkoutHeartRates? = nil) -> Workout {
        Workout(
            session: "20261103/071000", start: at("2026-11-03T06:10:00Z"), end: at("2026-11-03T06:52:00Z"), utcOffsetSeconds: 3600, bandSportId: 1,
            durationSeconds: 2520, calories: calories, cardioLoad: nil, cardioLoadRating: nil, trainingLoad: nil, averageHeartRate: nil,
            maxHeartRate: nil, heartRates: heartRates, fileSize: 1, unreadableFiles: [])
    }

    let calories = ActivityDay.Calories(bmr: 1728, activity: 900, total: 2628)

    /// The workout's resting share is 1728 × 2520 ÷ 86 400 = 50.4 kcal, so it carries 449.6; the day keeps 900 − 449.6 = 450.4.
    @Test func theDaysActiveEnergyLeavesTheWorkoutsOutOnlyWhenWorkoutsAreAllowed() {
        let allowed = HealthMapping.energy(
            day: day("2026-11-03"), calories: calories, utcOffsetSeconds: 3600, readAt: at("2026-11-04T08:00:00Z"), workouts: [workout()])
        let notAllowed = HealthMapping.energy(
            day: day("2026-11-03"), calories: calories, utcOffsetSeconds: 3600, readAt: at("2026-11-04T08:00:00Z"), workouts: nil)

        #expect(abs((HealthMapping.activeEnergy(workout(), bmr: 1728) ?? 0) - 449.6) < 1e-9)
        #expect(allowed.map(\.type) == [.activeEnergy, .restingEnergy])
        guard case .quantity(let active, .kcal) = allowed[0].value else { Issue.record("not kcal"); return }
        #expect(abs(active - 450.4) < 1e-9)
        #expect(allowed[1].value == .quantity(1728, .kcal))
        #expect(notAllowed[0].value == .quantity(900, .kcal))
        #expect(allowed.map(\.start) == [at("2026-11-02T23:00:00Z"), at("2026-11-02T23:00:00Z")])
        #expect(allowed.map(\.end) == [at("2026-11-03T23:00:00Z"), at("2026-11-03T23:00:00Z")])
        #expect(allowed.map(\.syncId) == ["vesel.activeEnergy.2026-11-03", "vesel.restingEnergy.2026-11-03"])
    }

    /// Today runs to when the daily summary was read. A workout without calories takes nothing off the day and has no energy.
    @Test func todayEndsAtTheReadAndAWorkoutWithoutCaloriesCarriesNoEnergy() {
        let items = HealthMapping.energy(
            day: day("2026-11-03"), calories: calories, utcOffsetSeconds: 3600, readAt: at("2026-11-03T12:00:00Z"),
            workouts: [workout(calories: nil)])
        let label = WorkoutLabel(sport: .running, source: .band, hidden: false)
        let written = HealthMapping.workout(workout(calories: nil), label: label, route: [], bmr: 1728, dayHeartRates: [])

        #expect(items.map(\.end) == [at("2026-11-03T12:00:00Z"), at("2026-11-03T12:00:00Z")])
        #expect(items[0].value == .quantity(900, .kcal))
        guard case .workout(let saved)? = written?.value else { Issue.record("not a workout"); return }
        #expect(saved.samples.isEmpty)
    }

    /// The Loop's own readings, 0 left out; the Loop's sport; the route as given.
    @Test func aWorkoutCarriesItsEnergyOwnHeartRateSportAndRoute() throws {
        let route = [RoutePoint(time: at("2026-11-03T06:20:00Z"), latitude: 52.5, longitude: 13.4, accuracy: 5)]
        let item = try #require(
            HealthMapping.workout(
                workout(heartRates: WorkoutHeartRates(intervalMs: 60_000, bpm: [120, 0, 130])), label: WorkoutLabel(sport: .running, source: .band, hidden: false),
                route: route, bmr: 1728,
                dayHeartRates: [HeartRateSample(time: at("2026-11-03T06:30:00Z"), bpm: 99, trigger: .timed)]))

        #expect(item.type == .workout)
        #expect(item.syncId == "vesel.workout.20261103/071000")
        #expect(item.start == at("2026-11-03T06:10:00Z"))
        #expect(item.end == at("2026-11-03T06:52:00Z"))
        guard case .workout(let saved) = item.value else { Issue.record("not a workout"); return }
        #expect(saved.activity == .running)
        #expect(saved.route == route)
        #expect(saved.samples.map(\.type) == [.activeEnergy, .heartRate, .heartRate])
        #expect(saved.samples.dropFirst().map(\.value) == [.quantity(120, .bpm), .quantity(130, .bpm)])
        #expect(saved.samples.dropFirst().map(\.start) == [at("2026-11-03T06:10:00Z"), at("2026-11-03T06:12:00Z")])
        #expect(saved.samples[1].syncId == "vesel.workout.20261103/071000.hr.\(Int64(at("2026-11-03T06:10:00Z").timeIntervalSince1970) * 1000)")
    }

    /// Without its own readings it takes the 24/7 ones inside it; a guessed sport is Other; no route is fine; hidden writes nothing.
    @Test func aGuessIsOtherAndAHiddenWorkoutIsNothing() throws {
        let day = [
            HeartRateSample(time: at("2026-11-03T06:00:00Z"), bpm: 70, trigger: .timed),
            HeartRateSample(time: at("2026-11-03T06:30:00Z"), bpm: 140, trigger: .timed),
        ]
        let guessed = try #require(
            HealthMapping.workout(workout(), label: WorkoutLabel(sport: .cycling, source: .speed, hidden: false), route: [], bmr: 1728, dayHeartRates: day))

        guard case .workout(let saved) = guessed.value else { Issue.record("not a workout"); return }
        #expect(saved.activity == .other)
        #expect(saved.route.isEmpty)
        #expect(saved.samples.filter { $0.type == .heartRate }.map(\.value) == [.quantity(140, .bpm)])
        #expect(HealthMapping.workout(workout(), label: WorkoutLabel(sport: .running, source: .owner, hidden: true), route: [], bmr: 0, dayHeartRates: day) == nil)
    }

    @Test func theDaysReadingsInsideAWorkoutAreLeftOut() {
        let samples = [
            HeartRateSample(time: at("2026-11-03T06:00:00Z"), bpm: 70, trigger: .timed),
            HeartRateSample(time: at("2026-11-03T06:30:00Z"), bpm: 140, trigger: .timed),
        ]

        #expect(HealthMapping.heartRate(samples, leavingOut: [workout().interval]).map(\.value) == [.quantity(70, .bpm)])
    }

    @Test func aWorkoutUnitIsOrderedByItsSessionsDay() {
        let unit = HealthUnit(kind: .workout, key: "20261103/071000")
        #expect(HealthUnit(id: unit.id) == unit)
        #expect(unit.day == nil)
        #expect(unit.date == "2026-11-03")
    }
}
