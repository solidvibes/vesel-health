import Foundation
@preconcurrency import PolarBleSdk
import SwiftProtobuf
import Testing
import VeselCore
@testable import VeselWearable

/// Built from the SDK's own protobuf structs, never a real session file.
struct PolarMappingWorkoutTests {
    func time(_ hour: UInt32, _ minute: UInt32, offsetMinutes: Int32?) -> PbLocalDateTime {
        var time = PbLocalDateTime()
        time.date.year = 2026
        time.date.month = 11
        time.date.day = 3
        time.time.hour = hour
        time.time.minute = minute
        time.time.seconds = 0
        time.time.millis = 0
        if let offsetMinutes { time.timeZoneOffset = offsetMinutes }
        return time
    }

    func summary(offsetMinutes: Int32? = 60) -> Data_PbTrainingSession {
        var summary = Data_PbTrainingSession()
        summary.start = time(7, 10, offsetMinutes: offsetMinutes)
        summary.end = time(7, 55, offsetMinutes: offsetMinutes)
        summary.duration.minutes = 42
        summary.calories = 410
        summary.heartRate.average = 148
        summary.heartRate.maximum = 171
        summary.cardioLoad.exerciseLoad = 87.5
        summary.cardioLoadInterpretation = 3
        summary.trainingLoad.trainingLoadVal = 64
        summary.sport.value = 1
        return summary
    }

    func session(_ summary: Data_PbTrainingSession, samples: Data_PbExerciseSamples? = nil, listed: [PolarExerciseDataTypes] = []) -> PolarTrainingSession {
        let exercise = PolarExercise(
            index: 0, path: "/U/0/20261103/E/071000/00", exerciseDataTypes: [.exerciseSummary, .samplesGzip] + listed,
            exerciseSummary: Data_PbExerciseBase(), samples: samples
        )
        let reference = PolarTrainingSessionReference(
            date: at("2026-11-03T06:10:00Z"), path: "/U/0/20261103/E/071000/TSESS.BPB", trainingDataTypes: [.trainingSessionSummary],
            exercises: [exercise], fileSize: 4_321
        )
        return PolarTrainingSession(reference: reference, sessionSummary: summary, exercises: [exercise])
    }

    func samples(intervalSeconds: UInt32) -> Data_PbExerciseSamples {
        var samples = Data_PbExerciseSamples()
        samples.recordingInterval.seconds = intervalSeconds
        samples.heartRateSamples = [120, 131, 140]
        return samples
    }

    @Test func aWorkoutKeepsItsTimesNumbersAndFiles() throws {
        let band = try PolarMapping.workout(session(summary(), samples: samples(intervalSeconds: 1)), zone: berlin)
        let workout = band.workout
        #expect(workout.session == "20261103/071000")
        #expect(workout.start == at("2026-11-03T06:10:00Z"))
        #expect(workout.end == at("2026-11-03T06:55:00Z"))
        #expect(workout.utcOffsetSeconds == 3600)
        #expect(workout.day == day("2026-11-03"))
        #expect(workout.durationSeconds == 42 * 60)
        #expect(workout.bandSportId == 1)
        #expect(workout.calories == 410)
        #expect(workout.cardioLoad == 87.5)
        #expect(workout.cardioLoadRating == 3)
        #expect(workout.trainingLoad == 64)
        #expect(workout.averageHeartRate == 148)
        #expect(workout.maxHeartRate == 171)
        #expect(workout.heartRates == WorkoutHeartRates(intervalMs: 1000, bpm: [120, 131, 140]))
        #expect(workout.fileSize == 4_321)
        #expect(workout.unreadableFiles.isEmpty)
        #expect(band.files.map(\.name) == ["TSESS", "00/BASE", "00/SAMPLES"])
        let kept = try Data_PbTrainingSession(serializedBytes: try #require(band.files.first?.data), partial: true)
        #expect(kept == summary())
    }

    /// The band gave no offset: read in the phone's zone, unless the phone is at UTC too.
    @Test func aStartWithoutAnOffsetIsReadInThePhonesZone() throws {
        let inBerlin = try PolarMapping.workout(session(summary(offsetMinutes: nil)), zone: berlin).workout
        #expect(inBerlin.start == at("2026-11-03T06:10:00Z"))
        #expect(inBerlin.utcOffsetSeconds == 3600)
        let inUTC = try PolarMapping.workout(session(summary(offsetMinutes: 0)), zone: TimeZone(identifier: "UTC")!).workout
        #expect(inUTC.start == at("2026-11-03T07:10:00Z"))
        #expect(inUTC.utcOffsetSeconds == 0)
    }

    /// The SDK hides whether a value was set, so 0 reads as absent; a rating outside 1–5 is dropped.
    @Test func zeroMeansAbsent() throws {
        var bare = summary()
        bare.calories = 0
        bare.heartRate.average = 0
        bare.heartRate.maximum = 0
        bare.cardioLoad.exerciseLoad = 0
        bare.cardioLoadInterpretation = 7
        bare.trainingLoad.trainingLoadVal = 0
        bare.sport.value = 0
        let workout = try PolarMapping.workout(session(bare, samples: samples(intervalSeconds: 0)), zone: berlin).workout
        #expect(workout.calories == nil)
        #expect(workout.averageHeartRate == nil)
        #expect(workout.maxHeartRate == nil)
        #expect(workout.cardioLoad == nil)
        #expect(workout.cardioLoadRating == nil)
        #expect(workout.trainingLoad == nil)
        #expect(workout.bandSportId == nil)
        #expect(workout.heartRates == nil)
    }

    /// Only a cardio load is kept as given: the training load stays absent, not made up from it.
    @Test func eachLoadIsKeptOnItsOwn() throws {
        var only = summary()
        only.trainingLoad.trainingLoadVal = 0
        only.cardioLoadInterpretation = 0
        let workout = try PolarMapping.workout(session(only), zone: berlin).workout
        #expect(workout.cardioLoad == 87.5)
        #expect(workout.cardioLoadRating == nil)
        #expect(workout.trainingLoad == nil)
    }

    @Test func aListedFileThatDidNotParseIsUnreadable() throws {
        let band = try PolarMapping.workout(session(summary(), listed: [.route]), zone: berlin)
        #expect(band.workout.unreadableFiles == ["00/SAMPLES", "00/ROUTE"])
        #expect(band.files.map(\.name) == ["TSESS", "00/BASE"])
    }

    @Test func aWorkoutWithoutALengthIsUnfinished() throws {
        var running = summary()
        running.duration = PbDuration()
        #expect(throws: WorkoutReadError.unfinished) { try PolarMapping.workout(session(running), zone: berlin) }
    }

    @Test func aReferenceNamesItsFolderAndFiles() {
        let reference = session(summary(), listed: [.routeGzip]).reference
        #expect(PolarMapping.workoutSession(reference.path) == "20261103/071000")
        #expect(PolarMapping.workoutFileNames(reference) == ["TSESS", "00/BASE", "00/ROUTE", "00/SAMPLES"])
    }
}
