import Foundation

/// What the stress row and widget say right now: a level for a reading under 30 minutes old, "Learning" before
/// 7 days of readings. One implementation for Today and the widgets.
public struct StressGlance: Sendable, Equatable {
    public var ringText: String
    public var rowText: String

    public static let unknown = StressGlance(ringText: "—", rowText: "—")

    public init(ringText: String, rowText: String) {
        self.ringText = ringText
        self.rowText = rowText
    }

    public init(days: Int, now: StressNow?, at date: Date) {
        guard days >= StressThresholds.minimumDays else {
            self.init(ringText: "Learning", rowText: "Learning your normal")
            return
        }
        guard let now, now.isRecent(at: date) else {
            self.init(ringText: "—", rowText: "No recent reading")
            return
        }
        let word = now.band.word.prefix(1).uppercased() + now.band.word.dropFirst()
        self.init(ringText: word, rowText: "\(word) · \(Int(now.level.rounded()))")
    }
}
