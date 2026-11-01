import Foundation
@preconcurrency import PolarBleSdk
import Testing
import VeselCore
@testable import VeselWearable
import VeselWearableTesting

/// Berlin: clocks go back at 03:00 on 2026-10-25 (to 02:00) and forward at 02:00 on 2027-03-28 (to 03:00).
struct ClockChangeTests {
    let back = day("2026-10-25")
    let forward = day("2027-03-28")

    func heartRates(_ times: [(Int, Int)], on day: DayKey) throws -> [Date] {
        struct Sample: Encodable { var time: DateComponents; var hrSamples: [UInt32]; var triggerType: String }
        struct Data247: Encodable { var date: DateComponents; var samples: [Sample] }
        let data = try JSONDecoder().decode(
            Polar247HrSamplesData.self,
            from: JSONEncoder().encode(
                Data247(
                    date: DateComponents(year: day.year, month: day.month, day: day.day),
                    samples: times.map { .init(time: DateComponents(hour: $0.0, minute: $0.1, second: 0), hrSamples: [60], triggerType: "timed") }
                )))
        guard case .heartRates(let samples) = try PolarMapping.heartRates([data], day: day, zone: berlin).content() else { return [] }
        return samples.map(\.time)
    }

    @Test func goingBackTheRepeatedHourIsReadTwiceInOrder() throws {
        #expect(
            try heartRates([(0, 30), (2, 50), (2, 10), (4, 0)], on: back) == [
                at("2026-10-24T22:30:00Z"), at("2026-10-25T00:50:00Z"), at("2026-10-25T01:10:00Z"), at("2026-10-25T03:00:00Z"),
            ])
    }

    /// The band keeps summer time until a sync sets it back, here at 03:20 summer time.
    @Test func goingBackTheBandKeepsSummerTimeUntilItsClockStepsBack() throws {
        #expect(
            try heartRates([(0, 30), (3, 10), (2, 20), (3, 10), (5, 0)], on: back) == [
                at("2026-10-24T22:30:00Z"), at("2026-10-25T01:10:00Z"), at("2026-10-25T01:20:00Z"), at("2026-10-25T02:10:00Z"), at("2026-10-25T04:00:00Z"),
            ])
    }

    @Test func goingBackWithoutAStepTheRepeatedHourIsItsFirstPass() throws {
        #expect(
            try heartRates([(1, 0), (2, 30), (5, 0)], on: back) == [
                at("2026-10-24T23:00:00Z"), at("2026-10-25T00:30:00Z"), at("2026-10-25T04:00:00Z"),
            ])
    }

    /// A time in the skipped hour means the band hadn't been set forward yet.
    @Test func goingForwardTimesAfterTheChangeAreSummerTime() throws {
        #expect(
            try heartRates([(1, 30), (2, 15), (3, 30), (23, 0)], on: forward) == [
                at("2027-03-28T00:30:00Z"), at("2027-03-28T01:15:00Z"), at("2027-03-28T01:30:00Z"), at("2027-03-28T21:00:00Z"),
            ])
    }

    @Test func sleepTimesKeepTheirOwnOffsetAcrossTheChange() throws {
        struct Result: Encodable { var sleepStartTime: Date; var sleepEndTime: Date; var sleepWakePhases: [String] = [] }
        let result = try JSONDecoder().decode(
            PolarSleepData.PolarSleepAnalysisResult.self,
            from: JSONEncoder().encode(
                Result(
                    sleepStartTime: at("2026-10-24T20:46:00Z"), sleepEndTime: at("2026-10-25T04:51:00Z")
                )))
        let payload = try PolarMapping.sleep(result, day: back, zone: berlin)
        #expect(payload.json.contains(#""sleepStartTime":"2026-10-24T22:46:00+02:00""#))
        #expect(payload.json.contains(#""sleepEndTime":"2026-10-25T05:51:00+01:00""#))
        guard case .sleep(let night) = try payload.content() else { Issue.record("no night"); return }
        #expect(night.start == at("2026-10-24T20:46:00Z"))
        #expect(night.end == at("2026-10-25T04:51:00Z"))
    }

    @Test func ppiSessionsInTheRepeatedHourKeepTheirOffset() throws {
        struct Session: Encodable {
            var startTime: String; var triggerType = "TRIGGER_TYPE_AUTOMATIC"; var ppiValueList: [Int32] = [1000]; var ppiErrorEstimateList: [Int32] = [5];
            var statusList: [String] = []
        }
        struct Data247: Encodable { var date: DateComponents; var samples: [Session] }
        let data = try JSONDecoder().decode(
            Polar247PPiSamplesData.self,
            from: JSONEncoder().encode(
                Data247(
                    date: DateComponents(year: 2026, month: 10, day: 25), samples: [.init(startTime: "02:40:00.000"), .init(startTime: "02:15:00.000")]
                )))
        guard case .ppi(let sessions) = try PolarMapping.ppi([data], day: back, zone: berlin).content() else { Issue.record("no sessions"); return }
        #expect(sessions.map(\.start) == [at("2026-10-25T00:40:00Z"), at("2026-10-25T01:15:00Z")])
        #expect(sessions.map(\.utcOffsetSeconds) == [7200, 3600])
    }

    @Test func skinTemperatureGoingForward() throws {
        struct Sample: Encodable { var recordingTimeDeltaMs: UInt64; var temperature: Float }
        struct Result: Encodable { var date: Date; var skinTemperatureList: [Sample] }
        let result = try JSONDecoder().decode(
            PolarSkinTemperatureData.PolarSkinTemperatureResult.self,
            from: JSONEncoder().encode(
                Result(
                    date: at("2027-03-28T12:00:00Z"),
                    skinTemperatureList: [.init(recordingTimeDeltaMs: 5_400_000, temperature: 34), .init(recordingTimeDeltaMs: 12_600_000, temperature: 34)]
                )))
        guard case .skinTemperatures(let samples) = try PolarMapping.skinTemperature(result, day: forward, zone: berlin).content() else {
            Issue.record("no samples"); return
        }
        #expect(samples.map(\.time) == [at("2027-03-28T00:30:00Z"), at("2027-03-28T01:30:00Z")])
    }

    /// Payloads stored before times carried an offset are still read in the day's offset.
    @Test func timesWithoutAnOffsetUseThePayloadsOffset() throws {
        let payload = BandPayload(
            day: back, kind: .heartRate, json: #"{"date":"2026-10-25","samples":[{"time":"04:00:00","hr":60}]}"#, utcOffsetSeconds: 3600, sampleCount: 1)
        #expect(try payload.content() == .heartRates([HeartRateSample(time: at("2026-10-25T03:00:00Z"), bpm: 60, trigger: .unknown)]))
    }

    @Test func theFakeBandsChangeNightHasNoGapOrOverlap() async throws {
        let payload = try await FakeWearableSource(scenario: .normal).fetch(.heartRate, from: back, through: back)[0]
        guard case .heartRates(let samples) = try payload.content() else { Issue.record("no samples"); return }
        #expect(samples.count == 300)
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $1.time.timeIntervalSince($0.time) == 300 })
        guard case .sleep(let night) = try await FakeWearableSource(scenario: .normal).fetch(.sleep, from: back, through: back)[0].content() else { return }
        #expect(night.start == at("2026-10-24T20:46:00Z"))
    }
}
