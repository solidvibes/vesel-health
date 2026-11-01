import Foundation

/// Heart fitness: how your estimated VO2max compares with your age, worked out once a month on read. Never stored.
public struct FitnessInputs: Sendable, Equatable {
    public var profile: Profile
    /// The window's nights of resting heart rate (bpm), in any order.
    public var restingHeartRates: [Double]
    /// The window's days that have a daily summary.
    public var days: [FitnessDay]

    public init(profile: Profile, restingHeartRates: [Double], days: [FitnessDay]) {
        self.profile = profile
        self.restingHeartRates = restingHeartRates
        self.days = days
    }
}

/// One day's seconds per activity class, as the daily summary has them.
public struct FitnessDay: Sendable, Equatable {
    public var day: DayKey
    public var classSeconds: [String: Int]

    public init(day: DayKey, classSeconds: [String: Int]) {
        self.day = day
        self.classSeconds = classSeconds
    }

    func seconds(_ keys: String...) -> Int { keys.reduce(0) { $0 + (classSeconds[$1] ?? 0) } }

    var isWorn: Bool { seconds("nonWear") < FitnessAge.maximumNonWearSeconds }
    var moderateAndVigorousSeconds: Int { seconds("continuousModerate", "intermittentModerate", "continuousVigorous", "intermittentVigorous") }
    var vigorousSeconds: Int { seconds("continuousVigorous", "intermittentVigorous") }
}

public enum FitnessBand: String, Sendable, Equatable {
    case younger, about, older

    public var title: String {
        switch self {
        case .younger: "Younger than your age"
        case .about: "About your age"
        case .older: "Older than your age"
        }
    }

    /// For VoiceOver: "Heart fitness: younger than your age".
    public var spoken: String { "Heart fitness: \(title.lowercasedFirst)" }
}

private extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}

/// What stood for body size: your waist when About you has one (the HUNT waist model), else BMI (its BMI model).
public enum FitnessBody: Sendable, Equatable {
    case waist(cm: Double)
    case bmi(Double)
}

public struct FitnessEstimate: Sendable, Equatable {
    public var band: FitnessBand
    public var age: Int
    public var fitnessAge: Int
    public var vo2max: Double
    public var body: FitnessBody
    public var restingHeartRate: Double
    public var exerciseDaysPerWeek: Double
    public var exerciseMinutes: Double
    public var activityIndex: Double
    /// The last day of the month the estimate is about.
    public var windowEnd: DayKey
    public var explanation: Explanation
}

public enum FitnessOutcome: Sendable, Equatable {
    case learning
    case outsideAgeRange
    case estimate(FitnessEstimate)
}

public enum FitnessAge {
    public static let minimumNights = 7
    public static let minimumWornDays = 14
    public static let windowDays = 28
    public static let ageRange = 20...90
    static let maximumNonWearSeconds = 4 * 3600
    static let exerciseDaySeconds = 15 * 60
    static let vigorousSeconds = 10 * 60
    static let method = "fitness.estimate"
    public static let restingHeartRateKind = "recovery.restingHeartRate"

    /// The 28 days ending on the last day of the month before `today`'s.
    public static func window(today: DayKey) -> (first: DayKey, last: DayKey) {
        let last = DayKey(year: today.year, month: today.month, day: 1).adding(days: -1)
        return (last.adding(days: -(windowDays - 1)), last)
    }

    /// The 1st of the month after `today`'s: when the next estimate is worked out.
    public static func nextWorkedOut(today: DayKey) -> DayKey {
        today.month == 12 ? DayKey(year: today.year + 1, month: 1, day: 1) : DayKey(year: today.year, month: today.month + 1, day: 1)
    }

    public static func estimate(_ inputs: FitnessInputs, today: DayKey) -> FitnessOutcome {
        let windowEnd = window(today: today).last
        let age = windowEnd.year - inputs.profile.birthYear
        guard ageRange.contains(age) else { return .outsideAgeRange }
        let worn = inputs.days.filter(\.isWorn)
        guard inputs.restingHeartRates.count >= minimumNights, worn.count >= minimumWornDays else { return .learning }

        let body: FitnessBody =
            inputs.profile.waistCm.map { .waist(cm: $0) }
            ?? {
                let height = inputs.profile.heightCm / 100
                return .bmi(inputs.profile.weightKg / (height * height))
            }()
        let restingHeartRate = median(inputs.restingHeartRates)
        let exercise = worn.filter { $0.moderateAndVigorousSeconds >= exerciseDaySeconds }
        let perWeek = Double(exercise.count) * 7 / Double(worn.count)
        let minutes = median(exercise.map { Double($0.moderateAndVigorousSeconds) / 60 })
        let vigorousDays = exercise.filter { $0.vigorousSeconds >= vigorousSeconds }.count
        let index = activityIndex(perWeek: perWeek, minutes: minutes, vigorousDays: vigorousDays, exerciseDays: exercise.count)

        let vo2max = Self.vo2max(sex: inputs.profile.sex, age: Double(age), body: body, restingHeartRate: restingHeartRate, index: index)
        let fitnessAge =
            switch inputs.profile.sex {
            case .male: 160.7 - 2.513 * vo2max
            case .female: 155.8 - 3.049 * vo2max
            }
        let capped = Int(min(fitnessAge, age < 70 ? 80 : 90).rounded())
        let result = max(ageRange.lowerBound, capped)
        let band = band(age: age, fitnessAge: result)

        let bodyInputs: [Explanation.Input] =
            switch body {
            case .waist(let cm): [.init(name: "model", value: 1, unit: "waist"), .init(name: "waist", value: cm, unit: "cm")]
            case .bmi(let bmi): [.init(name: "model", value: 0, unit: "bmi"), .init(name: "bmi", value: bmi, unit: "kg/m²")]
            }
        let numbers: [Explanation.Input] =
            [.init(name: "age", value: Double(age), unit: "years")] + bodyInputs + [
                .init(name: "restingHeartRate", value: restingHeartRate, unit: "bpm"),
                .init(name: "exerciseDaysPerWeek", value: perWeek, unit: "days/week"),
                .init(name: "exerciseMinutes", value: minutes, unit: "min"),
                .init(name: "activityIndex", value: index, unit: "points"),
                .init(name: "vo2max", value: vo2max, unit: "ml/kg/min"),
                .init(name: "fitnessAge", value: Double(result), unit: "years"),
            ]
        return .estimate(
            FitnessEstimate(
                band: band, age: age, fitnessAge: result, vo2max: vo2max, body: body, restingHeartRate: restingHeartRate,
                exerciseDaysPerWeek: perWeek, exerciseMinutes: minutes, activityIndex: index, windowEnd: windowEnd,
                explanation: Explanation(method: method, version: 2, inputs: numbers, text: text(age: age, result: result, body: body, band: band))
            ))
    }

    /// HUNT's models (Nes et al. 2011): the waist model when there is a waist, else the BMI model. ml/kg/min.
    static func vo2max(sex: Sex, age: Double, body: FitnessBody, restingHeartRate: Double, index: Double) -> Double {
        switch (sex, body) {
        case (.male, .waist(let waist)): 100.27 - 0.296 * age + 0.226 * index - 0.369 * waist - 0.155 * restingHeartRate
        case (.female, .waist(let waist)): 74.736 - 0.247 * age + 0.198 * index - 0.259 * waist - 0.114 * restingHeartRate
        case (.male, .bmi(let bmi)): 92.05 - 0.327 * age - 0.933 * bmi - 0.167 * restingHeartRate + 0.257 * index
        case (.female, .bmi(let bmi)): 70.77 - 0.244 * age - 0.749 * bmi - 0.107 * restingHeartRate + 0.213 * index
        }
    }

    /// "About" is within 5 years either way, edges included.
    static func band(age: Int, fitnessAge: Int) -> FitnessBand {
        let difference = fitnessAge - age
        return difference < -5 ? .younger : (difference > 5 ? .older : .about)
    }

    /// Vesel's mapping of the band's moderate and vigorous minutes onto the HUNT questionnaire's three answers, multiplied.
    static func activityIndex(perWeek: Double, minutes: Double, vigorousDays: Int, exerciseDays: Int) -> Double {
        let frequency: Double = perWeek < 1 ? 0 : (perWeek < 2 ? 1 : (perWeek < 4 ? 2 : 3))
        let duration = minutes >= 30 ? 1.5 : 1
        let intensity: Double = exerciseDays > 0 && vigorousDays * 2 >= exerciseDays ? 5 : 1
        return frequency * duration * intensity
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private static func text(age: Int, result: Int, body: FitnessBody, band: FitnessBand) -> String {
        let model: String
        let source: String
        switch body {
        case .waist:
            model = "with your waist from About you"
            source = """
                The coefficients are the waist model as reprinted in an open HUNT paper (PMC7428991) and used by the study group's own calculator, \
                and the fitness age uses that calculator's formula. One standard error is 5.7 ml/kg/min for men and 5.1 for women, 10 or more years of fitness age.
                """
        case .bmi:
            model = "with BMI in place of waist (no waist in About you)"
            source = """
                The coefficients are the model as reprinted in open HUNT papers, and the fitness age uses the study group's own calculator formula. \
                One standard error is about 5 to 6 ml/kg/min (the waist version's figure; the BMI version's is not published), 10 or more years of fitness age.
                """
        }
        let measure = if case .waist = body { "waist" } else { "BMI" }
        return """
            An estimate from a population model, not a fitness test. It uses the Norwegian HUNT study's model without exercise \
            (Nes et al. 2011, 2014), \(model): VO2max from your age (\(age), the year of the month it is about minus your birth year), \
            \(measure), resting heart rate (the median of the month's nights) and an activity index, then the age whose average VO2max \
            matches yours (\(result)). Within 5 years of your age counts as "about" it: \(band.title.lowercased()).
            \(source)
            The activity index is Vesel's own mapping of the Loop's moderate and vigorous minutes onto the questionnaire: an exercise day has at least 15 minutes; \
            frequency is exercise days a week (4 or more counts as almost every day), duration is the median minutes on those days (30 or more is the higher answer), \
            intensity is "some heavy breathing" when at least half of them have 10 minutes of vigorous time, otherwise easy. \
            It never says "all out", because the Loop can't tell. This mapping moves the result more than anything else you can change.
            The study measured resting heart rate awake; yours is from sleep and usually lower, so the result leans younger.
            """
    }
}
