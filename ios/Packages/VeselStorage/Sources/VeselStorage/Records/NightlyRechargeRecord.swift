import Foundation
import GRDB
import VeselCore

struct NightlyRechargeRecord: UpsertRecord {
    static let databaseTableName = "nightly_recharge"
    static let keyColumns: Set<String> = ["night"]

    var night: String
    var createdAt: Int64?
    var modifiedAt: Int64?
    var ansStatus: Double?
    var recoveryIndicator: Int?
    var recoveryIndicatorSubLevel: Int?
    var ansRate: Int?
    var scoreRateObsolete: Int?
    var meanNightlyRecoveryRri: Int?
    var meanNightlyRecoveryRmssd: Int?
    var meanNightlyRecoveryRespirationInterval: Int?
    var meanBaselineRri: Int?
    var sdBaselineRri: Int?
    var meanBaselineRmssd: Int?
    var sdBaselineRmssd: Int?
    var meanBaselineRespirationInterval: Int?
    var sdBaselineRespirationInterval: Int?
    var sleepTip: String?
    var vitalityTip: String?
    var exerciseTip: String?
    var rawJson: String

    init(_ recharge: NightlyRecharge, rawJSON: String) {
        night = recharge.night.description
        createdAt = recharge.createdAt?.unixSeconds
        modifiedAt = recharge.modifiedAt?.unixSeconds
        ansStatus = recharge.ansStatus
        recoveryIndicator = recharge.recoveryIndicator
        recoveryIndicatorSubLevel = recharge.recoveryIndicatorSubLevel
        ansRate = recharge.ansRate
        scoreRateObsolete = recharge.scoreRateObsolete
        meanNightlyRecoveryRri = recharge.meanNightlyRecoveryRRI
        meanNightlyRecoveryRmssd = recharge.meanNightlyRecoveryRMSSD
        meanNightlyRecoveryRespirationInterval = recharge.meanNightlyRecoveryRespirationInterval
        meanBaselineRri = recharge.meanBaselineRRI
        sdBaselineRri = recharge.sdBaselineRRI
        meanBaselineRmssd = recharge.meanBaselineRMSSD
        sdBaselineRmssd = recharge.sdBaselineRMSSD
        meanBaselineRespirationInterval = recharge.meanBaselineRespirationInterval
        sdBaselineRespirationInterval = recharge.sdBaselineRespirationInterval
        sleepTip = recharge.sleepTip
        vitalityTip = recharge.vitalityTip
        exerciseTip = recharge.exerciseTip
        rawJson = rawJSON
    }

    func model() throws -> NightlyRecharge {
        NightlyRecharge(
            night: try DayKey(stored: night),
            createdAt: createdAt.map(Date.init(unixSeconds:)),
            modifiedAt: modifiedAt.map(Date.init(unixSeconds:)),
            ansStatus: ansStatus,
            recoveryIndicator: recoveryIndicator,
            recoveryIndicatorSubLevel: recoveryIndicatorSubLevel,
            ansRate: ansRate,
            scoreRateObsolete: scoreRateObsolete,
            meanNightlyRecoveryRRI: meanNightlyRecoveryRri,
            meanNightlyRecoveryRMSSD: meanNightlyRecoveryRmssd,
            meanNightlyRecoveryRespirationInterval: meanNightlyRecoveryRespirationInterval,
            meanBaselineRRI: meanBaselineRri,
            sdBaselineRRI: sdBaselineRri,
            meanBaselineRMSSD: meanBaselineRmssd,
            sdBaselineRMSSD: sdBaselineRmssd,
            meanBaselineRespirationInterval: meanBaselineRespirationInterval,
            sdBaselineRespirationInterval: sdBaselineRespirationInterval,
            sleepTip: sleepTip,
            vitalityTip: vitalityTip,
            exerciseTip: exerciseTip
        )
    }
}
