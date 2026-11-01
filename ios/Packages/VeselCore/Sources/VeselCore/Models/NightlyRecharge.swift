import Foundation

/// Polar's Nightly Recharge for one night, every field as the band reports it.
public struct NightlyRecharge: Sendable, Equatable {
    public var night: DayKey
    public var createdAt: Date?
    public var modifiedAt: Date?
    public var ansStatus: Double?
    public var recoveryIndicator: Int?
    public var recoveryIndicatorSubLevel: Int?
    public var ansRate: Int?
    public var scoreRateObsolete: Int?
    public var meanNightlyRecoveryRRI: Int?
    public var meanNightlyRecoveryRMSSD: Int?
    public var meanNightlyRecoveryRespirationInterval: Int?
    public var meanBaselineRRI: Int?
    public var sdBaselineRRI: Int?
    public var meanBaselineRMSSD: Int?
    public var sdBaselineRMSSD: Int?
    public var meanBaselineRespirationInterval: Int?
    public var sdBaselineRespirationInterval: Int?
    public var sleepTip: String?
    public var vitalityTip: String?
    public var exerciseTip: String?

    public init(
        night: DayKey,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil,
        ansStatus: Double? = nil,
        recoveryIndicator: Int? = nil,
        recoveryIndicatorSubLevel: Int? = nil,
        ansRate: Int? = nil,
        scoreRateObsolete: Int? = nil,
        meanNightlyRecoveryRRI: Int? = nil,
        meanNightlyRecoveryRMSSD: Int? = nil,
        meanNightlyRecoveryRespirationInterval: Int? = nil,
        meanBaselineRRI: Int? = nil,
        sdBaselineRRI: Int? = nil,
        meanBaselineRMSSD: Int? = nil,
        sdBaselineRMSSD: Int? = nil,
        meanBaselineRespirationInterval: Int? = nil,
        sdBaselineRespirationInterval: Int? = nil,
        sleepTip: String? = nil,
        vitalityTip: String? = nil,
        exerciseTip: String? = nil
    ) {
        self.night = night
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.ansStatus = ansStatus
        self.recoveryIndicator = recoveryIndicator
        self.recoveryIndicatorSubLevel = recoveryIndicatorSubLevel
        self.ansRate = ansRate
        self.scoreRateObsolete = scoreRateObsolete
        self.meanNightlyRecoveryRRI = meanNightlyRecoveryRRI
        self.meanNightlyRecoveryRMSSD = meanNightlyRecoveryRMSSD
        self.meanNightlyRecoveryRespirationInterval = meanNightlyRecoveryRespirationInterval
        self.meanBaselineRRI = meanBaselineRRI
        self.sdBaselineRRI = sdBaselineRRI
        self.meanBaselineRMSSD = meanBaselineRMSSD
        self.sdBaselineRMSSD = sdBaselineRMSSD
        self.meanBaselineRespirationInterval = meanBaselineRespirationInterval
        self.sdBaselineRespirationInterval = sdBaselineRespirationInterval
        self.sleepTip = sleepTip
        self.vitalityTip = vitalityTip
        self.exerciseTip = exerciseTip
    }
}
