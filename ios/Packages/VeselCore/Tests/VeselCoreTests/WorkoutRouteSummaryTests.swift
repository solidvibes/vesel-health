import Foundation
import Testing
import VeselCore

struct WorkoutRouteSummaryTests {
    /// 06:10 to 06:52 UTC, 42 minutes.
    let workout = DateInterval(start: at("2026-11-03T06:10:00Z"), end: at("2026-11-03T06:52:00Z"))

    func point(_ time: String, lat: Double, lon: Double = 13.4, accuracy: Double = 8) -> RoutePoint {
        RoutePoint(time: at(time), latitude: lat, longitude: lon, accuracy: accuracy)
    }

    /// The phone started 20 minutes late: 23 points a minute apart from 06:30 to 06:52, each 0.002° further north.
    @Test func aRouteThatStartsLateCoversPartOfTheWorkout() throws {
        var points = (0...22).map { minute in
            RoutePoint(
                time: at("2026-11-03T06:30:00Z").addingTimeInterval(Double(minute * 60)), latitude: 52.5 + 0.002 * Double(minute), longitude: 13.4, accuracy: 8)
        }
        // Before the workout, too inexact, and no accuracy at all: all dropped.
        points += [
            point("2026-11-03T06:05:00Z", lat: 52.0), point("2026-11-03T06:40:30Z", lat: 53.0, accuracy: 30),
            point("2026-11-03T06:41:30Z", lat: 53.0, accuracy: -1),
        ]
        let summary = WorkoutRouteSummary(points: points.reversed(), workout: workout, durationSeconds: 42 * 60)

        #expect(summary.points.count == 23)
        // Each leg along a meridian is R × 0.002° in radians: 6 371 008.8 × 0.0000349066 = 222.390 m; 22 legs = 4 892.58 m.
        #expect(abs(summary.distanceMeters - 4892.5835) < 0.01)
        #expect(summary.coveredSeconds == 1320)
        // 4 892.58 m ÷ 1 320 s × 3.6 = 13.343 km/h.
        #expect(abs(try #require(summary.averageSpeedKmh) - 13.3434) < 0.001)
        // 22 of 42 minutes.
        #expect(abs(summary.coverage - 0.5238) < 0.0001)
        #expect(summary.coversEnough)
    }

    /// East–west at 52.5° N: 0.003° of longitude is 203.074 m (haversine), shorter than at the equator.
    @Test func distanceAcrossLongitudeFollowsTheLatitude() {
        let summary = WorkoutRouteSummary(
            points: [point("2026-11-03T06:20:00Z", lat: 52.5), point("2026-11-03T06:21:00Z", lat: 52.5, lon: 13.403)], workout: workout,
            durationSeconds: 42 * 60)
        #expect(abs(summary.distanceMeters - 203.0738) < 0.001)
        #expect(!summary.coversEnough)
    }

    @Test func noPointsCoverNothing() {
        let summary = WorkoutRouteSummary(points: [], workout: workout, durationSeconds: 42 * 60)
        #expect(summary.distanceMeters == 0)
        #expect(summary.coverage == 0)
        #expect(summary.averageSpeedKmh == nil)
    }
}
