import Foundation
import Testing
import VeselCore
@testable import VeselStorage

/// The phone's route: written again every minute under its start, joined to the workout it overlaps most, backed up.
struct RouteStorageTests {
    let database: AppDatabase
    let now = at("2026-11-03T09:00:00Z")

    init() throws {
        database = try AppDatabase.inMemory()
    }

    func route(from start: String, minutes: Int, ended: Bool = true) -> RecordedRoute {
        let begin = at(start)
        let points = (0..<(minutes * 12)).map { index in
            RoutePoint(
                time: begin.addingTimeInterval(Double(index) * 5), latitude: 52.520_008 + Double(index) * 0.000_01,
                longitude: 13.404_954, accuracy: 6)
        }
        return RecordedRoute(start: begin, end: ended ? begin.addingTimeInterval(Double(minutes * 60)) : nil, points: points)
    }

    func workout(from start: String, minutes: Int) -> Workout {
        let begin = at(start)
        return Workout(
            session: "20261103/071000", start: begin, end: begin.addingTimeInterval(Double(minutes * 60)), utcOffsetSeconds: 3600,
            bandSportId: nil, durationSeconds: minutes * 60, calories: nil, cardioLoad: nil, cardioLoadRating: nil, trainingLoad: nil,
            averageHeartRate: nil, maxHeartRate: nil, heartRates: nil, fileSize: 1, unreadableFiles: [])
    }

    @Test func eachWriteReplacesTheRouteSoFarAndAWriteWithNothingNewKeepsTheBackupMark() async throws {
        let partial = route(from: "2026-11-03T06:10:00Z", minutes: 1, ended: false)
        try await database.save(partial, updatedAt: now)
        let whole = route(from: "2026-11-03T06:10:00Z", minutes: 42)
        try await database.save(whole, updatedAt: now)
        #expect(try await database.count("workout_route") == 1)

        try await database.markAllUploaded(at: 1)
        try await database.save(whole, updatedAt: now.addingTimeInterval(60))
        #expect(try await database.uploadedAt("workout_route", where: "1") == 1)

        var longer = whole
        longer.points.append(RoutePoint(time: at("2026-11-03T06:52:05Z"), latitude: 52.53, longitude: 13.41, accuracy: 5))
        try await database.save(longer, updatedAt: now.addingTimeInterval(120))
        #expect(try await database.uploadedAt("workout_route", where: "1") == nil)
        #expect(try await database.route(for: workout(from: "2026-11-03T06:10:00Z", minutes: 42)) == longer)
    }

    @Test func aRouteJoinsTheWorkoutItOverlapsMost() async throws {
        try await database.save(route(from: "2026-11-03T05:30:00Z", minutes: 45), updatedAt: now)
        try await database.save(route(from: "2026-11-03T06:30:00Z", minutes: 30), updatedAt: now)
        try await database.save(route(from: "2026-11-03T08:00:00Z", minutes: 10, ended: false), updatedAt: now)
        let run = workout(from: "2026-11-03T06:10:00Z", minutes: 42)

        #expect(try await database.routes(overlapping: DateInterval(start: run.start, end: run.end)).count == 2)
        #expect(try await database.route(for: run)?.start == at("2026-11-03T06:30:00Z"))
        #expect(try await database.route(for: workout(from: "2026-11-03T08:05:00Z", minutes: 20))?.start == at("2026-11-03T08:00:00Z"))
        #expect(try await database.route(for: workout(from: "2026-11-03T12:00:00Z", minutes: 20)) == nil)
    }

    @Test func aRouteGoesToTheMacKeyedByItsStart() async throws {
        let ride = route(from: "2026-11-03T06:10:00Z", minutes: 1)
        try await database.save(ride, updatedAt: now)

        let upload = try #require(try await database.pendingUploads(.workoutRoute, limit: 10, now: now).first)
        #expect(upload.key == String(at("2026-11-03T06:10:00Z").unixSeconds))
        #expect(upload.data["updated_at"] == .integer(now.unixSeconds))
        guard case .text(let json) = upload.data["points_json"] else { Issue.record("points_json isn't text"); return }
        #expect(try JSONDecoder().decode([RoutePoint].self, from: Data(json.utf8)) == ride.points)
    }

    /// One point every 5 s for the longest route keeps a row far below the upload's 4 MB batch.
    @Test func aSixHourRouteStaysUnderHalfAMegabyte() async throws {
        let longest = route(from: "2026-11-03T03:00:00Z", minutes: Int(WorkoutThresholds.routeMaxHours * 60))
        #expect(longest.points.count == 4_320)
        try await database.save(longest, updatedAt: now)

        let upload = try #require(try await database.pendingUploads(.workoutRoute, limit: 1, now: now).first)
        guard case .text(let json) = upload.data["points_json"] else { Issue.record("points_json isn't text"); return }
        #expect(json.utf8.count < 500_000)
    }
}
