import GRDB
import VeselCore

struct ProfileRecord: UpsertRecord {
    static let databaseTableName = "profile"
    static let keyColumns: Set<String> = ["id"]
    /// Spelled out: snake case can't round-trip `measured_vo2max` (the digit splits it).
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.useDefaultKeys
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.useDefaultKeys

    enum CodingKeys: String, CodingKey {
        case id
        case birthYear = "birth_year"
        case sex
        case heightCm = "height_cm"
        case weightKg = "weight_kg"
        case sleepGoalMinutes = "sleep_goal_minutes"
        case waistCm = "waist_cm"
        case measuredVO2max = "measured_vo2max"
    }

    var id = 1
    var birthYear: Int
    var sex: String
    var heightCm: Double
    var weightKg: Double
    var sleepGoalMinutes: Int
    var waistCm: Double?
    var measuredVO2max: Double?

    init(_ profile: Profile) {
        birthYear = profile.birthYear
        sex = profile.sex.rawValue
        heightCm = profile.heightCm
        weightKg = profile.weightKg
        sleepGoalMinutes = profile.sleepGoalMinutes
        waistCm = profile.waistCm
        measuredVO2max = profile.measuredVO2max
    }

    var model: Profile? {
        Sex(rawValue: sex).map {
            Profile(
                birthYear: birthYear, sex: $0, heightCm: heightCm, weightKg: weightKg, sleepGoalMinutes: sleepGoalMinutes,
                waistCm: waistCm, measuredVO2max: measuredVO2max
            )
        }
    }
}
