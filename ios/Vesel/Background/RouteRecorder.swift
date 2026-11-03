import CoreLocation
import UIKit
import VeselCore
import VeselStorage

/// Records the phone's route from the Loop's workout start notice to its end notice, only with Record my route on and
/// location allowed, and at most `routeMaxHours`. Points stay in memory, one per `routePointSeconds`, and the route so far
/// is written every minute and at the end, each write in its own background time; a write that finds the database paused
/// waits for the next one. Never logs a location.
@MainActor
final class RouteRecorder {
    static let writeEvery: TimeInterval = 60

    private let database: AppDatabase
    private let clock: any VeselClock
    private var route: RecordedRoute?
    private var recording: Task<Void, Never>?
    private var limit: Task<Void, Never>?
    private var activity: CLBackgroundActivitySession?
    private var lastWrite = Date.distantPast
    /// Writes run one after another, so an earlier write never lands over the final one.
    private var lastWriteTask: Task<Void, Never>?

    init(database: AppDatabase, clock: any VeselClock) {
        self.database = database
        self.clock = clock
    }

    func start(at start: Date) async {
        let maxDuration = WorkoutThresholds.routeMaxHours * 3600
        guard route == nil, clock.now.timeIntervalSince(start) < maxDuration else { return }
        let time = BackgroundTime.begin("Route", database: database) {}
        let isOn = (try? await database.isRouteRecordingOn()) == true
        time.end()
        guard isOn, route == nil, LocationPermission.canRecord(whileOpen: UIApplication.shared.applicationState == .active) else { return }

        route = RecordedRoute(start: start, end: nil, points: [])
        lastWrite = clock.now
        activity = CLBackgroundActivitySession()
        recording = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                    guard let location = update.location else { continue }
                    await self?.received(location)
                }
            } catch {}
        }
        let remaining = maxDuration - clock.now.timeIntervalSince(start)
        limit = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            await self?.stop(at: start.addingTimeInterval(maxDuration))
        }
    }

    func stop(at end: Date) async {
        guard var route else { return }
        self.route = nil
        recording?.cancel()
        recording = nil
        limit?.cancel()
        limit = nil
        activity?.invalidate()
        activity = nil
        route.end = end
        await write(route)
    }

    private func received(_ location: CLLocation) async {
        // iOS may hand over a fix from before the workout first: never keep one.
        guard var route, location.horizontalAccuracy >= 0, location.timestamp >= route.start else { return }
        if let last = route.points.last, location.timestamp.timeIntervalSince(last.time) < WorkoutThresholds.routePointSeconds { return }
        route.points.append(
            RoutePoint(
                time: location.timestamp, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                accuracy: location.horizontalAccuracy))
        self.route = route
        if clock.now.timeIntervalSince(lastWrite) >= Self.writeEvery { await write(route) }
    }

    private func write(_ route: RecordedRoute) async {
        guard !route.points.isEmpty else { return }
        let previous = lastWriteTask
        let task = Task { [database, clock] in
            await previous?.value
            let time = BackgroundTime.begin("Route", database: database) {}
            let saved = (try? await database.save(route, updatedAt: clock.now)) != nil
            time.end()
            if saved { self.lastWrite = clock.now }
        }
        lastWriteTask = task
        await task.value
    }
}
