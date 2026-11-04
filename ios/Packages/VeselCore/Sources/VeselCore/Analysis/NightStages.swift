import Foundation

/// The deep, light and REM minutes of one night, as stored by the sleep summary.
public struct NightStages: Sendable, Equatable {
    public var night: DayKey
    public var deep: Double
    public var light: Double
    public var rem: Double

    public init(night: DayKey, deep: Double, light: Double, rem: Double) {
        self.night = night
        self.deep = deep
        self.light = light
        self.rem = rem
    }
}
