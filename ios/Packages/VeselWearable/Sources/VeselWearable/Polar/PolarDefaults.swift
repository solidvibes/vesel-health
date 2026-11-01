import VeselCore

/// First-time-setup values Vesel doesn't ask for, from Polar's FirstTimeUse guide.
enum PolarDefaults {
    static let restingHeartRate = 60

    static func maxHeartRate(age: Int) -> Int {
        min(max(220 - age, 100), 240)
    }

    /// The middle of the "Fair" band in Polar's VO2max table for the age group (training background "occasional").
    /// Ages outside the table use its nearest row.
    static func vo2Max(age: Int, sex: Sex) -> Int {
        let fair: [(lower: Int, upper: Int)] =
            switch sex {
            case .male: [(38, 43), (36, 42), (35, 40), (33, 38), (32, 35), (30, 34), (28, 32), (27, 30), (25, 28)]
            case .female: [(32, 36), (31, 35), (30, 33), (28, 31), (26, 29), (24, 27), (23, 25), (21, 23), (19, 21)]
            }
        let row = min(max((age - 20) / 5, 0), fair.count - 1)
        return (fair[row].lower + fair[row].upper) / 2
    }
}
