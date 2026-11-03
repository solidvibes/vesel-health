import Foundation

/// One location the phone recorded during a workout.
public struct RoutePoint: Sendable, Equatable, Codable {
    public var time: Date
    public var latitude: Double
    public var longitude: Double
    /// Horizontal accuracy in metres.
    public var accuracy: Double

    public init(time: Date, latitude: Double, longitude: Double, accuracy: Double) {
        self.time = time
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
    }
}

/// What a workout's route says: the points kept, the distance, and how much of the workout it covers. Worked out on read.
public struct WorkoutRouteSummary: Sendable, Equatable {
    /// Earth's mean radius, metres.
    static let earthRadius = 6_371_008.8

    /// Inside the workout and exact to 25 m, in time order.
    public var points: [RoutePoint]
    /// The sum of the straight (great-circle) lines between kept points.
    public var distanceMeters: Double
    /// First kept point to last.
    public var coveredSeconds: Double
    /// Covered time ÷ the workout's length.
    public var coverage: Double

    /// Distance ÷ covered time; nil when the route covers no time.
    public var averageSpeedKmh: Double? {
        coveredSeconds > 0 ? distanceMeters / coveredSeconds * 3.6 : nil
    }

    /// Enough of the workout to show a speed and guess from it.
    public var coversEnough: Bool { coverage >= WorkoutThresholds.routeMinCoverage }

    public init(points: [RoutePoint], workout: DateInterval, durationSeconds: Int) {
        let kept = points
            .filter { workout.contains($0.time) && $0.accuracy >= 0 && $0.accuracy <= WorkoutThresholds.routeAccuracyMeters }
            .sorted { $0.time < $1.time }
        self.points = kept
        distanceMeters = zip(kept, kept.dropFirst()).map { Self.distance($0, $1) }.reduce(0, +)
        coveredSeconds = kept.last.map { $0.time.timeIntervalSince(kept[0].time) } ?? 0
        coverage = durationSeconds > 0 ? coveredSeconds / Double(durationSeconds) : 0
    }

    /// Haversine distance in metres.
    static func distance(_ a: RoutePoint, _ b: RoutePoint) -> Double {
        let radians = Double.pi / 180
        let φ1 = a.latitude * radians
        let φ2 = b.latitude * radians
        let Δφ = φ2 - φ1
        let Δλ = (b.longitude - a.longitude) * radians
        let h = pow(sin(Δφ / 2), 2) + cos(φ1) * cos(φ2) * pow(sin(Δλ / 2), 2)
        return 2 * earthRadius * asin(min(1, h.squareRoot()))
    }
}
