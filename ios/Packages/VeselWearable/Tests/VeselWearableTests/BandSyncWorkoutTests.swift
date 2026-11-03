import Foundation
import Testing
import VeselCore
import VeselStorage
import VeselWearable
import VeselWearableTesting

/// The fake band has the evening ride of Oct 24 and the morning run of Oct 25.
struct BandSyncWorkoutTests {
    let clock = TestClock("2026-10-26T07:00:00Z")
    let database: AppDatabase
    let band: FakeWearableSource
    let sync: BandSync
    let ride = "20261024/183000"
    let run = "20261025/071000"

    init() async throws {
        database = try AppDatabase.inMemory()
        try await database.save(BandInfo(deviceId: "FAKE0001", name: "Polar Loop", pairedAt: at("2026-09-26T08:00:00Z")))
        band = try FakeWearableSource(scenario: .normal)
        sync = BandSync(band: band, database: database, clock: clock)
    }

    func reads() async -> [String] {
        await band.calls.filter { $0.hasPrefix("workout ") }
    }

    func storedSessions() async throws -> [String] {
        try await database.storedWorkouts().keys.sorted()
    }

    @Test func readsEveryWorkoutBetweenSkinTemperatureAndHeartRateAndNeverDeletesOne() async throws {
        #expect(await sync.sync(.manual) == .success)

        #expect(try await storedSessions() == [ride, run])
        let stored = try await database.workouts(day: day("2026-10-25"))
        #expect(stored.first?.workout.cardioLoad == 87)
        #expect(stored.first?.workout.bandSportId == 1)
        let calls = await band.calls
        let skin = try #require(calls.firstIndex(of: "fetch skinTemperature"))
        let heartRate = try #require(calls.firstIndex(of: "fetch heartRate"))
        let workoutCalls = calls.indices.filter { ["workoutStatus", "workoutReferences"].contains(calls[$0]) || calls[$0].hasPrefix("workout ") }
        #expect(workoutCalls.count == 4)
        #expect(workoutCalls.allSatisfy { $0 > skin && $0 < heartRate })
        #expect(!calls.contains { $0.hasPrefix("delete") && $0.contains("workout") })
        #expect(await band.workoutSessions.sorted() == [ride, run])
    }

    @Test func aStoredWorkoutIsReadAgainOnlyWhenItsFilesChangeSize() async throws {
        await sync.sync(.manual)
        await band.clearCalls()
        clock.set("2026-10-26T08:00:00Z")
        await sync.sync(.manual)
        #expect(await reads().isEmpty)

        var changed = try #require(try await database.workouts(day: day("2026-10-25")).first).workout
        changed.fileSize += 10
        changed.cardioLoad = 90
        await band.putWorkout(BandWorkout(workout: changed, files: [WorkoutFile(name: "TSESS", data: Data([1]))]))
        clock.set("2026-10-26T09:00:00Z")
        await sync.sync(.manual)

        #expect(await reads() == ["workout \(run)"])
        #expect(try await database.workouts(day: day("2026-10-25")).first?.workout.cardioLoad == 90)
    }

    /// A file that didn't parse comes back the same every time: it is kept as unreadable and not asked for again.
    @Test func anUnreadableFileIsNotReadAgainWithoutASizeChange() async throws {
        await sync.sync(.manual)
        var workout = try #require(try await database.workouts(day: day("2026-10-25")).first).workout
        workout.fileSize += 5
        workout.unreadableFiles = ["00/SAMPLES"]
        await band.putWorkout(BandWorkout(workout: workout, files: []))
        clock.set("2026-10-26T08:00:00Z")
        await sync.sync(.manual)
        await band.clearCalls()
        clock.set("2026-10-26T09:00:00Z")
        await sync.sync(.manual)

        #expect(await reads().isEmpty)
        #expect(try await database.workouts(day: day("2026-10-25")).first?.workout.unreadableFiles == ["00/SAMPLES"])
    }

    @Test func theRunningWorkoutWaitsForItsEnd() async throws {
        await band.setWorkoutStatus(.running(since: at("2026-10-25T06:10:30Z")))
        await sync.sync(.manual)
        #expect(try await storedSessions() == [ride])

        await band.setWorkoutStatus(.notRunning)
        clock.set("2026-10-26T08:00:00Z")
        await sync.sync(.manual)
        #expect(try await storedSessions() == [ride, run])
    }

    /// Without a start time, workouts from the last 6 hours not yet stored wait.
    @Test func aRunningWorkoutWithoutAStartHoldsBackTheLastSixHours() async throws {
        clock.set("2026-10-25T10:00:00Z")
        await band.setWorkoutStatus(.running(since: nil))
        await sync.sync(.manual)
        #expect(try await storedSessions() == [ride])
    }

    @Test func aWorkoutThatFailsIsSkippedAndTriedAgainAfterAnHour() async throws {
        await band.setFailure(.workoutTransfer)
        #expect(await sync.sync(.manual) == .success)
        #expect(try await storedSessions() == [run])
        #expect(try await database.ledger([.heartRate]).isEmpty == false)

        await band.setFailure(nil)
        await band.clearCalls()
        clock.set("2026-10-26T07:30:00Z")
        await sync.sync(.manual)
        #expect(await reads().isEmpty)

        clock.set("2026-10-26T08:01:00Z")
        await sync.sync(.manual)
        #expect(await reads() == ["workout \(ride)"])
        #expect(try await storedSessions() == [ride, run])
    }

    /// A workout read the watchdog stops ends that read; the next one skips it for an hour and reaches heart rate.
    @Test func aStuckWorkoutReadDoesNotHoldBackTheNextReadsHeartRate() async throws {
        let uptime = ManualUptime()
        let band = try FakeWearableSource(scenario: .normal, uptime: uptime)
        let limits = ReadLimits(
            tapWait: .milliseconds(500), backgroundWait: .milliseconds(500), stuckCall: .milliseconds(50), backlogCall: .milliseconds(50),
            awayGrace: .seconds(2), tick: .milliseconds(10))
        let sync = BandSync(band: band, database: database, clock: clock, limits: limits, uptime: { uptime.now })
        await band.hangNext("workout \(ride)", for: .milliseconds(500))
        #expect(await sync.sync(.manual) != .success)

        await band.clearCalls()
        clock.set("2026-10-26T07:30:00Z")
        #expect(await sync.sync(.manual) == .success)
        let calls = await band.calls
        #expect(!calls.contains("workout \(ride)"))
        #expect(calls.contains("fetch heartRate"))
        await band.answerHangs()
    }

    @Test func anUnfinishedWorkoutIsSkipped() async throws {
        await sync.sync(.manual)
        var workout = try #require(try await database.workouts(day: day("2026-10-25")).first).workout
        workout.session = "20261026/060000"
        workout.durationSeconds = 0
        await band.putWorkout(BandWorkout(workout: workout, files: []))
        clock.set("2026-10-26T08:00:00Z")
        #expect(await sync.sync(.manual) == .success)
        #expect(try await storedSessions() == [ride, run])
    }

    @Test func detectionIsSwitchedOnOnceKeepingTheLoopsOwnValues() async throws {
        await band.setDetection(WorkoutDetection(isOn: false, sensitivity: 70, minimumMinutes: 15))
        await sync.sync(.manual)

        let on = WorkoutDetection(isOn: true, sensitivity: 70, minimumMinutes: 15)
        #expect(await band.detection == on)
        #expect(try await database.workoutDetection() == on)
        let calls = await band.calls
        #expect(try #require(calls.firstIndex(of: "setTime")) < (try #require(calls.firstIndex(of: "setWorkoutDetection"))))

        await band.clearCalls()
        clock.set("2026-10-26T08:00:00Z")
        await sync.sync(.manual)
        #expect(await !band.calls.contains { $0.hasPrefix("setWorkoutDetection") || $0 == "workoutDetection" })
    }

    @Test func aLoopWithoutDetectionGetsWhatTheSDKWouldWrite() async throws {
        await sync.sync(.manual)
        #expect(await band.detection == .sdkFallback)
        #expect(try await database.workoutDetection() == .sdkFallback)
    }

    @Test func aRefusedSwitchOnIsTriedAgainNextReadAndTheReadCarriesOn() async throws {
        await band.setFailure(.workoutDetection)
        #expect(await sync.sync(.manual) == .success)
        #expect(try await !database.isWorkoutDetectionSetUp())
        #expect(try await storedSessions() == [ride, run])

        await band.setFailure(nil)
        clock.set("2026-10-26T08:00:00Z")
        await sync.sync(.manual)
        #expect(try await database.workoutDetection() == .sdkFallback)
    }

    @Test func aDetectionChangePausesTheLiveStreamAndResumesItAfter() async throws {
        await sync.startLiveHeartRate()
        await band.clearCalls()
        let detection = WorkoutDetection(isOn: true, sensitivity: 30, minimumMinutes: 20)

        try await sync.setWorkoutDetection(detection)
        #expect(await band.calls == ["stopLiveHeartRate", "setWorkoutDetection", "startLiveHeartRate"])
        #expect(await band.detection == detection)

        await band.setFailure(.workoutDetection)
        await #expect(throws: FakeBandError.refused) { try await sync.setWorkoutDetection(.sdkFallback) }
        #expect(await sync.isStreaming)
        #expect(await band.detection == detection)
    }
}
