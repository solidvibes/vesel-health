import Foundation

/// What the Recovery page and the headline say about the contributors: the one furthest from your usual, in words, and the
/// one quiet line when a low night has no single cause.
public enum RecoverySentence {
    /// Shown only when Polar says 3 or lower, at least one row has a mark and every marked row is inside: a low verdict is never left unexplained.
    public static func quietLine(status: RecoveryStatus?, contributors: [ContributorReading]) -> String? {
        guard let status, status.indicator <= 3 else { return nil }
        let marks = contributors.compactMap(\.mark)
        guard !marks.isEmpty, marks.allSatisfy({ $0 == .inside }) else { return nil }
        return Headline.noneStoodOut
    }

    /// The contributor furthest from your usual, when it is more than 1 standard deviation away.
    public static func driver(_ contributors: [ContributorReading]) -> ContributorReading? {
        contributors.compactMap { reading in reading.spreads.map { (reading, $0) } }
            .filter { abs($0.1) > 1 }
            .max { abs($0.1) < abs($1.1) }?.0
    }

    static func describe(_ reading: ContributorReading, units: Units) -> String {
        let direction = (reading.difference ?? 0) > 0 ? "above" : "below"
        let amount = abs(reading.difference ?? 0)
        switch reading.contributor {
        case .hrv:
            let percent = reading.range.map { $0.mean != 0 ? amount / $0.mean * 100 : 0 } ?? 0
            return "HRV \(NumberText.decimal(percent, 0)) % \(direction) your usual"
        case .restingHeartRate:
            return "Resting heart rate \(NumberText.decimal(amount, 0)) bpm \(direction) your usual"
        case .breathing:
            return "Breathing \(NumberText.decimal(amount, 1)) breaths/min \(direction) your usual"
        case .sleep:
            return "Sleep \(DurationText.hoursMinutes(minutes: amount)) \(direction == "above" ? "longer" : "shorter") than usual"
        case .skinTemperature:
            return "Skin temperature \(NumberText.decimal(units.temperatureDifference(celsius: amount), 1)) \(units.temperatureUnit) \(direction) your usual"
        }
    }
}
