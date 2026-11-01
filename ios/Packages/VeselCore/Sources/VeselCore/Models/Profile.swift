public struct Profile: Sendable, Equatable {
    public var birthYear: Int
    public var sex: Sex
    public var heightCm: Double
    public var weightKg: Double
    public var sleepGoalMinutes: Int
    /// Optional, phone only: with it, heart fitness uses the waist model.
    public var waistCm: Double?
    /// Optional, phone only: a VO2max another device measured, shown beside Vesel's estimate and never used in it.
    public var measuredVO2max: Double?

    public init(
        birthYear: Int, sex: Sex, heightCm: Double, weightKg: Double, sleepGoalMinutes: Int,
        waistCm: Double? = nil, measuredVO2max: Double? = nil
    ) {
        self.birthYear = birthYear
        self.sex = sex
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.sleepGoalMinutes = sleepGoalMinutes
        self.waistCm = waistCm
        self.measuredVO2max = measuredVO2max
    }

    /// True when the fields the Loop keeps are the same; waist and the outside VO2max stay on the phone.
    public func sameOnBand(as other: Profile) -> Bool {
        birthYear == other.birthYear && sex == other.sex && heightCm == other.heightCm
            && weightKg == other.weightKg && sleepGoalMinutes == other.sleepGoalMinutes
    }
}

public enum Sex: String, Sendable, Codable {
    case male, female
}
