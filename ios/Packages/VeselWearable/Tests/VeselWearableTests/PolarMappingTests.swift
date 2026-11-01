import Foundation
@preconcurrency import PolarBleSdk
import Testing
import VeselCore
@testable import VeselWearable

/// The SDK's result types have no public initializers, so the tests build them by decoding their own Codable form.
struct PolarMappingTests {
    let night = day("2026-10-20")
    let offset = 7200
    let zone = berlin

    func sdk<T: Decodable>(_ type: T.Type, from value: some Encodable) throws -> T {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(value))
    }

    func date(_ day: Int) -> DateComponents {
        DateComponents(year: 2026, month: 10, day: day)
    }

    func clock(_ hour: Int, _ minute: Int, _ second: Int = 0) -> DateComponents {
        DateComponents(hour: hour, minute: minute, second: second)
    }

    @Test func sleepKeepsItsTimesAndStages() throws {
        struct Phase: Encodable { var secondsFromSleepStart: UInt32; var state: String }
        struct Result: Encodable {
            var sleepStartTime: Date
            var sleepEndTime: Date
            var sleepGoalMinutes: UInt32
            var sleepWakePhases: [Phase]
            var sleepResultDate: DateComponents
        }
        let result = try sdk(
            PolarSleepData.PolarSleepAnalysisResult.self,
            from: Result(
                sleepStartTime: at("2026-10-19T21:05:00Z"),
                sleepEndTime: at("2026-10-20T04:50:00Z"),
                sleepGoalMinutes: 480,
                sleepWakePhases: [
                    .init(secondsFromSleepStart: 0, state: "NONREM12"), .init(secondsFromSleepStart: 1200, state: "NONREM3"),
                    .init(secondsFromSleepStart: 5400, state: "REM"),
                ],
                sleepResultDate: date(20)
            ))
        let payload = try PolarMapping.sleep(result, day: night, zone: zone)
        #expect(payload.sampleCount == 3)
        #expect(payload.json.contains(#""sleepStartTime":"2026-10-19T23:05:00+02:00""#))
        #expect(
            try payload.content()
                == .sleep(
                    SleepNight(
                        night: night,
                        start: at("2026-10-19T21:05:00Z"),
                        end: at("2026-10-20T04:50:00Z"),
                        goalMinutes: 480,
                        phases: [
                            .init(secondsFromStart: 0, state: .light), .init(secondsFromStart: 1200, state: .deep), .init(secondsFromStart: 5400, state: .rem),
                        ]
                    )))
    }

    @Test func noResultIsAnEmptyDay() throws {
        #expect(try PolarMapping.sleep(nil, day: night, zone: zone) == .empty(day: night, kind: .sleep, utcOffsetSeconds: offset))
        #expect(try PolarMapping.heartRates([], day: night, zone: zone).isEmpty)
        #expect(try PolarMapping.ppi([], day: night, zone: zone).isEmpty)
        #expect(try PolarMapping.dailySummary(nil, day: night, zone: zone).isEmpty)
    }

    @Test func heartRatesBecomeTimestampsOneSecondApart() throws {
        struct Sample: Encodable { var time: DateComponents; var hrSamples: [UInt32]; var triggerType: String }
        struct Data247: Encodable { var date: DateComponents; var samples: [Sample] }
        let data = try sdk(
            Polar247HrSamplesData.self,
            from: Data247(
                date: date(20),
                samples: [
                    .init(time: clock(6, 0), hrSamples: [52], triggerType: "timed"),
                    .init(time: clock(17, 30), hrSamples: [120, 121], triggerType: "highActivity"),
                ]))
        let payload = try PolarMapping.heartRates([data], day: night, zone: zone)
        #expect(payload.sampleCount == 3)
        #expect(
            try payload.content()
                == .heartRates([
                    HeartRateSample(time: at("2026-10-20T04:00:00Z"), bpm: 52, trigger: .timed),
                    HeartRateSample(time: at("2026-10-20T15:30:00Z"), bpm: 120, trigger: .highActivity),
                    HeartRateSample(time: at("2026-10-20T15:30:01Z"), bpm: 121, trigger: .highActivity),
                ]))
    }

    /// Clearing removes every 24/7 file of a day, so two files for the same day must both be stored.
    @Test func twoHeartRateFilesForOneDayAreBothKept() throws {
        struct Sample: Encodable { var time: DateComponents; var hrSamples: [UInt32]; var triggerType: String }
        struct Data247: Encodable { var date: DateComponents; var samples: [Sample] }
        let morning = try sdk(
            Polar247HrSamplesData.self, from: Data247(date: date(20), samples: [.init(time: clock(6, 0), hrSamples: [52], triggerType: "timed")]))
        let evening = try sdk(
            Polar247HrSamplesData.self, from: Data247(date: date(20), samples: [.init(time: clock(20, 0), hrSamples: [64], triggerType: "timed")]))
        let payload = try PolarMapping.heartRates([morning, evening], day: night, zone: zone)
        #expect(payload.sampleCount == 2)
    }

    @Test func ppiKeepsSessionsAndFlags() throws {
        struct Status: Encodable { var skinContact: String; var movement: String; var intervalStatus: String }
        struct Session: Encodable {
            var startTime: String
            var triggerType: String
            var ppiValueList: [Int32]
            var ppiErrorEstimateList: [Int32]
            var statusList: [Status]
        }
        struct Data247: Encodable { var date: DateComponents; var samples: [Session] }
        let data = try sdk(
            Polar247PPiSamplesData.self,
            from: Data247(
                date: date(20),
                samples: [
                    .init(
                        startTime: "03:00:00.250",
                        triggerType: "TRIGGER_TYPE_AUTOMATIC",
                        ppiValueList: [1000, 1010],
                        ppiErrorEstimateList: [5, 6],
                        statusList: [
                            .init(skinContact: "SKIN_CONTACT_DETECTED", movement: "MOVING_DETECTED", intervalStatus: "INTERVAL_IS_ONLINE"),
                            .init(skinContact: "SKIN_CONTACT_DETECTED", movement: "NO_MOVING_DETECTED", intervalStatus: "INTERVAL_IS_ONLINE"),
                        ]
                    )
                ]))
        let payload = try PolarMapping.ppi([data], day: night, zone: zone)
        #expect(payload.sampleCount == 2)
        let start = at("2026-10-20T01:00:00Z").addingTimeInterval(0.25)
        #expect(
            try payload.content()
                == .ppi([
                    PPISession(
                        start: start, trigger: .automatic, utcOffsetSeconds: offset,
                        samples: [
                            PPISample(time: start.addingTimeInterval(1.0), intervalMs: 1000, errorMs: 5, blocker: true, skinContact: true),
                            PPISample(time: start.addingTimeInterval(2.01), intervalMs: 1010, errorMs: 6, blocker: false, skinContact: true),
                        ])
                ]))
    }

    @Test func aBeatWithoutAStatusIsNotTreatedAsNoSkinContact() throws {
        struct Session: Encodable {
            var startTime: String
            var triggerType: String
            var ppiValueList: [Int32]
            var ppiErrorEstimateList: [Int32]
            var statusList: [String]
        }
        struct Data247: Encodable { var date: DateComponents; var samples: [Session] }
        let data = try sdk(
            Polar247PPiSamplesData.self,
            from: Data247(
                date: date(20),
                samples: [
                    .init(startTime: "03:00:00.000", triggerType: "TRIGGER_TYPE_AUTOMATIC", ppiValueList: [1000], ppiErrorEstimateList: [5], statusList: [])
                ]))
        let payload = try PolarMapping.ppi([data], day: night, zone: zone)
        let start = at("2026-10-20T01:00:00Z")
        #expect(
            try payload.content()
                == .ppi([
                    PPISession(
                        start: start, trigger: .automatic, utcOffsetSeconds: offset,
                        samples: [
                            PPISample(time: start.addingTimeInterval(1.0), intervalMs: 1000, errorMs: 5, blocker: false, skinContact: true)
                        ])
                ]))
    }

    @Test func skinTemperatureTimesCountFromTheBandsMidnight() throws {
        struct Sample: Encodable { var recordingTimeDeltaMs: UInt64; var temperature: Float }
        struct Result: Encodable { var date: Date; var sensorLocation: String; var measurementType: String; var skinTemperatureList: [Sample] }
        let result = try sdk(
            PolarSkinTemperatureData.PolarSkinTemperatureResult.self,
            from: Result(
                date: at("2026-10-20T12:00:00Z"), sensorLocation: "SL_DISTAL", measurementType: "TM_SKIN_TEMPERATURE",
                skinTemperatureList: [.init(recordingTimeDeltaMs: 3_900_000, temperature: 34.5)]
            ))
        let payload = try PolarMapping.skinTemperature(result, day: night, zone: zone)
        #expect(try payload.content() == .skinTemperatures([SkinTemperatureSample(time: at("2026-10-19T23:05:00Z"), celsius: 34.5)]))
    }

    @Test func aNumberThatIsNotFiniteIsLeftOut() throws {
        struct Sample: Encodable { var recordingTimeDeltaMs: UInt64; var temperature: Float }
        struct Result: Encodable { var date: Date; var skinTemperatureList: [Sample] }
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        let result = try decoder.decode(
            PolarSkinTemperatureData.PolarSkinTemperatureResult.self,
            from: encoder.encode(
                Result(
                    date: at("2026-10-20T12:00:00Z"),
                    skinTemperatureList: [.init(recordingTimeDeltaMs: 3_600_000, temperature: .nan), .init(recordingTimeDeltaMs: 3_900_000, temperature: 34.5)]
                )))
        let skin = try PolarMapping.skinTemperature(result, day: night, zone: zone)
        #expect(skin.sampleCount == 1)
        #expect(try skin.content() == .skinTemperatures([SkinTemperatureSample(time: at("2026-10-19T23:05:00Z"), celsius: 34.5)]))

        let recharge = try PolarMapping.recharge(
            RechargePayload(sleepResultDate: "2026-10-20", createdTimestamp: "2026-10-20T07:10:00", ansStatus: .infinity), day: night,
            utcOffsetSeconds: offset)
        #expect(!recharge.json.contains("ansStatus"))
    }

    @Test func activitySamplesKeepStepsMetAndClasses() throws {
        struct Info: Encodable { var activityClass: String; var timeStamp: Date; var factor: Float }
        struct Samples: Encodable {
            var startTime: Date
            var metRecordingInterval: Int
            var metSamples: [Float]
            var stepRecordingInterval: Int
            var stepSamples: [UInt32]
            var activityInfoList: [Info]
        }
        struct Activity: Encodable { var samples: Samples }
        struct DayData: Encodable { var polarActivityDataList: [Activity] }
        let data = try sdk(
            PolarActivityDayData.self,
            from: DayData(polarActivityDataList: [
                .init(
                    samples: .init(
                        startTime: at("2026-10-19T22:00:00Z"),
                        metRecordingInterval: 30, metSamples: [1.0, 1.5],
                        stepRecordingInterval: 60, stepSamples: [10, 20, 30],
                        activityInfoList: [.init(activityClass: "LIGHT", timeStamp: at("2026-10-20T06:00:00Z"), factor: 1)]
                    ))
            ]))
        let payload = try PolarMapping.activitySamples(data, day: night, zone: zone)
        #expect(payload.sampleCount == 6)
        #expect(payload.json.contains(#"{"steps":20,"time":"2026-10-20T00:01:00+02:00"}"#))
        #expect(try payload.content() == .none)
    }

    @Test func dailySummaryBecomesTheDaysActivity() throws {
        struct Time: Encodable { var hours = 0; var minutes = 0; var seconds = 0; var millis = 0 }
        struct Times: Encodable {
            var date: Date
            var timeNonWear = Time()
            var timeSleep = Time(hours: 7)
            var timeSedentary = Time(hours: 9)
            var timeLightActivity = Time(hours: 1, minutes: 30)
            var timeContinuousModerateActivity = Time(minutes: 20)
            var timeIntermittentModerateActivity = Time(minutes: 10)
            var timeContinuousVigorousActivity = Time(minutes: 5)
            var timeIntermittentVigorousActivity = Time()
        }
        struct Goal: Encodable {
            var activityGoal: Float = 100; var achievedActivity: Float = 80; var timeToGoUp: Time? = nil; var timeToGoWalk: Time? = nil;
            var timeToGoJog: Time? = nil
        }
        struct Summary: Encodable {
            var date: Date
            var activityCalories: UInt32 = 600
            var trainingCalories: UInt32 = 0
            var bmrCalories: UInt32 = 1700
            var steps: UInt32 = 9_000
            var activityGoalSummary = Goal()
            var activityClassTimes: Times
            var activityDistance: Float = 6_500
            var dailyBalanceFeedback = "NOT_CALCULATED"
            var readinessForSpeedAndStrengthTraining = "NOT_CALCULATED"
        }
        let noonUTC = at("2026-10-20T00:00:00Z")
        let summary = try sdk(PolarDailySummary.self, from: Summary(date: noonUTC, activityClassTimes: Times(date: noonUTC)))
        let payload = try PolarMapping.dailySummary(summary, day: night, zone: zone)
        #expect(
            try payload.content()
                == .activity(
                    ActivityDay(
                        day: night,
                        steps: 9_000,
                        activeSeconds: 2 * 3600 + 5 * 60,
                        calories: .init(bmr: 1700, activity: 600, total: 2300)
                    )))
    }

    @Test func nightlyRechargeKeepsEveryField() throws {
        let payload = try PolarMapping.recharge(
            RechargePayload(
                sleepResultDate: "2026-10-20",
                createdTimestamp: "2026-10-20T07:10:00",
                ansStatus: 4.5,
                recoveryIndicator: 4,
                meanNightlyRecoveryRMSSD: 46,
                meanBaselineRMSSD: 44,
                sleepTip: "Keep it up"
            ), day: night, utcOffsetSeconds: offset)
        #expect(
            try payload.content()
                == .nightlyRecharge(
                    NightlyRecharge(
                        night: night,
                        createdAt: at("2026-10-20T05:10:00Z"),
                        ansStatus: 4.5,
                        recoveryIndicator: 4,
                        meanNightlyRecoveryRMSSD: 46,
                        meanBaselineRMSSD: 44,
                        sleepTip: "Keep it up"
                    )))
    }

    @Test func firstTimeSetupDefaultsFollowPolarsGuide() {
        #expect(PolarDefaults.maxHeartRate(age: 36) == 184)
        #expect(PolarDefaults.vo2Max(age: 36, sex: .male) == 35)
        #expect(PolarDefaults.vo2Max(age: 36, sex: .female) == 29)
        #expect(PolarDefaults.vo2Max(age: 18, sex: .male) == 40)
        #expect(PolarDefaults.vo2Max(age: 80, sex: .female) == 20)
    }

    @Test(
        arguments: [
            ([UInt8](), 0),
            ([0x08, 0x00], 0),
            ([0x08, 0x05], 5),
            ([0x08, 0xAC, 0x02], 300),
            ([0x12, 0x02, 0xFF, 0xFF, 0x08, 0x03], 3),
        ] as [([UInt8], Int)])
    func inactivityCountdownReadsFieldOne(bytes: [UInt8], minutes: Int) {
        #expect(PolarMapping.inactivityCountdown(Data(bytes)) == minutes)
    }

    @Test(arguments: [[0x08], [0x08, 0x80], [0x12, 0x05, 0x01]] as [[UInt8]])
    func aTruncatedInactivityAlertIsUnreadable(bytes: [UInt8]) {
        #expect(PolarMapping.inactivityCountdown(Data(bytes)) == nil)
    }
}
