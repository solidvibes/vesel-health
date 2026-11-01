import Testing
@testable import VeselCore

struct FitnessAgeTests {
    static let today = DayKey("2026-10-02")!
    static let first = DayKey("2026-09-03")!
    static let restingNights: [Double] = [52, 55, 54, 58, 53, 55, 60]

    static let man = Profile(birthYear: 1986, sex: .male, heightCm: 180, weightKg: 81, sleepGoalMinutes: 480)
    static let woman = Profile(birthYear: 1986, sex: .female, heightCm: 160, weightKg: 64, sleepGoalMinutes: 480)

    /// 28 worn days; 12 exercise days of 35 minutes, 7 of them with 700 s vigorous time.
    static func month(exerciseDays: Int = 12, vigorousDays: Int = 7, nonWearOnFirst: Int = 0) -> [FitnessDay] {
        (0..<28).map { index in
            var seconds = ["nonWear": 0, "light": 9000]
            if index < exerciseDays {
                if index < vigorousDays {
                    seconds["continuousVigorous"] = 700
                    seconds["continuousModerate"] = 1400
                } else {
                    seconds["intermittentModerate"] = 2100
                }
            }
            if index == 27 { seconds["nonWear"] = nonWearOnFirst }
            return FitnessDay(day: first.adding(days: index), classSeconds: seconds)
        }
    }

    static func estimate(_ profile: Profile = man, nights: [Double] = restingNights, days: [FitnessDay] = month(), today: DayKey = today) -> FitnessOutcome {
        FitnessAge.estimate(FitnessInputs(profile: profile, restingHeartRates: nights, days: days), today: today)
    }

    static func result(_ outcome: FitnessOutcome) throws -> FitnessEstimate {
        guard case .estimate(let found) = outcome else { throw Missing() }
        return found
    }

    struct Missing: Error {}

    @Test func theWindowIsThe28DaysOfThePreviousMonth() {
        let window = FitnessAge.window(today: DayKey("2026-10-02")!)
        #expect(window.first == DayKey("2026-09-03")!)
        #expect(window.last == DayKey("2026-09-30")!)
        #expect(FitnessAge.window(today: DayKey("2027-01-15")!).last == DayKey("2026-12-31")!)
        #expect(FitnessAge.nextWorkedOut(today: DayKey("2026-12-31")!) == DayKey("2027-01-01")!)
        #expect(FitnessAge.nextWorkedOut(today: DayKey("2026-10-25")!) == DayKey("2026-11-01")!)
    }

    @Test func theMedianRestingHeartRateIs55() throws {
        #expect(try Self.result(Self.estimate()).restingHeartRate == 55)
    }

    @Test func bmiOf180cmAnd81kgIs25() throws {
        guard case .bmi(let bmi) = try Self.result(Self.estimate()).body else { Issue.record("no waist: BMI model"); return }
        #expect(abs(bmi - 25) < 1e-9)
    }

    @Test func twelveExerciseDaysIsThreeAWeekWithAMedianOf35Minutes() throws {
        let found = try Self.result(Self.estimate())
        #expect(found.exerciseDaysPerWeek == 3)
        #expect(found.exerciseMinutes == 35)
        // Frequency 2 (2 to 3 a week) × duration 1.5 (30 or more) × intensity 5 (vigorous on 7 of 12): 15.
        #expect(found.activityIndex == 15)
    }

    @Test func vigorousTimeOnFewerThanHalfTheExerciseDaysIsEasy() throws {
        // 5 of 12 is under half: intensity 1, index 2 × 1.5 × 1.
        #expect(try Self.result(Self.estimate(days: Self.month(vigorousDays: 5))).activityIndex == 3)
        // 6 of 12 is half: intensity 5.
        #expect(try Self.result(Self.estimate(days: Self.month(vigorousDays: 6))).activityIndex == 15)
    }

    @Test func noExerciseDaysGiveAnIndexOfZero() throws {
        let found = try Self.result(Self.estimate(days: Self.month(exerciseDays: 0, vigorousDays: 0)))
        #expect(found.activityIndex == 0)
        #expect(found.exerciseDaysPerWeek == 0)
    }

    @Test func frequencyAnswersFollowTheDaysAWeek() {
        #expect(FitnessAge.activityIndex(perWeek: 0.75, minutes: 40, vigorousDays: 0, exerciseDays: 3) == 0)
        #expect(FitnessAge.activityIndex(perWeek: 1, minutes: 20, vigorousDays: 0, exerciseDays: 4) == 1)
        #expect(FitnessAge.activityIndex(perWeek: 1.75, minutes: 20, vigorousDays: 0, exerciseDays: 7) == 1)
        #expect(FitnessAge.activityIndex(perWeek: 2, minutes: 20, vigorousDays: 0, exerciseDays: 8) == 2)
        #expect(FitnessAge.activityIndex(perWeek: 3.5, minutes: 20, vigorousDays: 0, exerciseDays: 14) == 2)
        #expect(FitnessAge.activityIndex(perWeek: 4, minutes: 30, vigorousDays: 16, exerciseDays: 16) == 3 * 1.5 * 5)
    }

    @Test func aManOf40Is34InFitnessAge() throws {
        let found = try Self.result(Self.estimate())
        #expect(found.age == 40)
        // 92.05 − 0.327·40 − 0.933·25 − 0.167·55 + 0.257·15 = 50.315
        #expect(abs(found.vo2max - 50.315) < 1e-9)
        // 160.7 − 2.513·50.315 = 34.258…
        #expect(found.fitnessAge == 34)
        #expect(found.band == .younger)
    }

    @Test func aWomanOf40Is37InFitnessAge() throws {
        let found = try Self.result(Self.estimate(Self.woman, nights: [60, 60, 60, 60, 60, 60, 60]))
        guard case .bmi(let bmi) = found.body else { Issue.record("no waist: BMI model"); return }
        #expect(abs(bmi - 25) < 1e-9)
        // 70.77 − 0.244·40 − 0.749·25 − 0.107·60 + 0.213·15 = 39.06
        #expect(abs(found.vo2max - 39.06) < 1e-9)
        // 155.8 − 3.049·39.06 = 36.706…
        #expect(found.fitnessAge == 37)
        #expect(found.band == .about)
    }

    @Test func sixNightsAreStillLearning() {
        #expect(Self.estimate(nights: Array(Self.restingNights.dropLast())) == .learning)
    }

    @Test func sevenNightsAnd13WornDaysAreStillLearning() {
        #expect(Self.estimate(days: Array(Self.month().prefix(13))) == .learning)
        if case .estimate = Self.estimate(days: Array(Self.month().prefix(14))) {} else { Issue.record("14 days should give an estimate") }
    }

    @Test func aDayWith5HoursNotWornIsNotWorn() {
        var days = Array(Self.month().prefix(14))
        days[13].classSeconds["nonWear"] = 5 * 3600
        #expect(Self.estimate(days: days) == .learning)
        days[13].classSeconds["nonWear"] = 4 * 3600 - 1
        if case .estimate = Self.estimate(days: days) {} else { Issue.record("under 4 hours is worn") }
    }

    @Test func agesOutsideTheModelHaveNoEstimate() {
        var young = Self.man
        young.birthYear = 2026 - 19
        #expect(Self.estimate(young) == .outsideAgeRange)
        var old = Self.man
        old.birthYear = 2026 - 91
        #expect(Self.estimate(old) == .outsideAgeRange)
        #expect(Self.estimate(young, nights: [], days: []) == .outsideAgeRange)
        var twenty = Self.man
        twenty.birthYear = 2026 - 20
        if case .estimate = Self.estimate(twenty) {} else { Issue.record("20 is in range") }
    }

    @Test func theBandSaysAboutWithin5YearsEitherWay() {
        #expect(FitnessAge.band(age: 40, fitnessAge: 34) == .younger)
        #expect(FitnessAge.band(age: 40, fitnessAge: 35) == .about)
        #expect(FitnessAge.band(age: 40, fitnessAge: 45) == .about)
        #expect(FitnessAge.band(age: 40, fitnessAge: 46) == .older)
    }

    @Test func theFitnessAgeIsCappedAndFloored() throws {
        // A very low resting heart rate and a light person at 25: fitness age would be under 20.
        var fit = Self.man
        fit.birthYear = 2026 - 25
        fit.weightKg = 60
        let young = try Self.result(Self.estimate(fit, nights: Array(repeating: 40, count: 7)))
        #expect(young.fitnessAge == 20)
        // An unfit 45-year-old: capped at 80.
        var unfit = Self.man
        unfit.birthYear = 2026 - 45
        unfit.weightKg = 140
        let capped = try Self.result(Self.estimate(unfit, nights: Array(repeating: 95, count: 7), days: Self.month(exerciseDays: 0, vigorousDays: 0)))
        #expect(capped.fitnessAge == 80)
    }

    @Test func theExplanationNamesTheMethodInputsAndPapers() throws {
        let explanation = try Self.result(Self.estimate()).explanation
        #expect(explanation.method == "fitness.estimate")
        #expect(explanation.version == 2)
        #expect(explanation.inputs.first { $0.name == "model" }.map { $0.value == 0 && $0.unit == "bmi" } == true)
        #expect(
            explanation.inputs.map(\.name) == [
                "age", "model", "bmi", "restingHeartRate", "exerciseDaysPerWeek", "exerciseMinutes", "activityIndex", "vo2max", "fitnessAge",
            ])
        #expect(explanation.text.contains("Nes et al. 2011, 2014"))
        #expect(explanation.text.contains("waist version"))
    }

    @Test func bandWordsAndSpokenLabel() {
        #expect(FitnessBand.younger.title == "Younger than your age")
        #expect(FitnessBand.about.title == "About your age")
        #expect(FitnessBand.older.title == "Older than your age")
        #expect(FitnessBand.younger.spoken == "Heart fitness: younger than your age")
    }

    @Test func aManOf40WithAWaistOf90UsesTheWaistModel() throws {
        var man = Self.man
        man.waistCm = 90
        let found = try Self.result(Self.estimate(man))
        #expect(found.body == .waist(cm: 90))
        // 100.27 − 0.296·40 + 0.226·15 − 0.369·90 − 0.155·55 = 100.27 − 11.84 + 3.39 − 33.21 − 8.525 = 50.085
        #expect(abs(found.vo2max - 50.085) < 1e-9)
        // 160.7 − 2.513·50.085 = 34.836…
        #expect(found.fitnessAge == 35)
        #expect(found.band == .about)
    }

    @Test func aWomanOf40WithAWaistOf80UsesTheWaistModel() throws {
        var woman = Self.woman
        woman.waistCm = 80
        let found = try Self.result(Self.estimate(woman, nights: [60, 60, 60, 60, 60, 60, 60]))
        #expect(found.body == .waist(cm: 80))
        // 74.736 − 0.247·40 + 0.198·15 − 0.259·80 − 0.114·60 = 74.736 − 9.88 + 2.97 − 20.72 − 6.84 = 40.266
        #expect(abs(found.vo2max - 40.266) < 1e-9)
        // 155.8 − 3.049·40.266 = 33.028…
        #expect(found.fitnessAge == 33)
        #expect(found.band == .younger)
    }

    @Test func theWaistModelIsChosenOnlyWithAWaist() throws {
        var man = Self.man
        #expect(try Self.result(Self.estimate(man)).body == .bmi(25))
        man.waistCm = 90
        let explanation = try Self.result(Self.estimate(man)).explanation
        #expect(explanation.version == 2)
        #expect(
            explanation.inputs.map(\.name) == [
                "age", "model", "waist", "restingHeartRate", "exerciseDaysPerWeek", "exerciseMinutes", "activityIndex", "vo2max", "fitnessAge",
            ])
        let model = try #require(explanation.inputs.first { $0.name == "model" })
        #expect(model.value == 1 && model.unit == "waist")
        #expect(explanation.inputs.first { $0.name == "waist" }?.value == 90)
        #expect(explanation.text.contains("with your waist"))
        #expect(explanation.text.contains("5.7 ml/kg/min for men"))
    }

    @Test func anOutsideVO2maxNeverChangesTheEstimate() throws {
        var man = Self.man
        man.measuredVO2max = 60
        #expect(try Self.result(Self.estimate(man)) == (try Self.result(Self.estimate())))
    }
}
