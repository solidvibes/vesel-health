import Foundation
import Observation
import VeselCore
import VeselStorage

@MainActor
@Observable
final class WorkoutSettingsModel {
    static let shortestChoices = [5, 10, 15, 20, 30, 45, 60]

    /// What the Loop has, as Vesel last wrote or read it; nil before the one-time switch-on.
    private(set) var detection: WorkoutDetection?
    private(set) var isLoaded = false
    private(set) var sports = Set(WorkoutSport.allCases)
    /// Record my route; on until turned off.
    private(set) var routeOn = true
    private(set) var saving = false
    /// The last band change didn't reach the Loop, so nothing changed on the phone; `failed` is what was tried.
    private(set) var failed: WorkoutDetection?

    private let database: AppDatabase
    private let idle: () async -> Void
    private let writeDetection: (WorkoutDetection) async -> Bool

    /// `writeDetection` writes to the Loop, then the phone; true once both have it. `idle` waits for a running read.
    init(database: AppDatabase, idle: @escaping () async -> Void, writeDetection: @escaping (WorkoutDetection) async -> Bool) {
        self.database = database
        self.idle = idle
        self.writeDetection = writeDetection
    }

    /// Shows what's stored now, then again once a running read has finished (it may switch detection on).
    func load() async {
        await read()
        await idle()
        await read()
    }

    private func read() async {
        if !saving { detection = try? await database.workoutDetection() }
        sports = (try? await database.workoutSports()) ?? sports
        routeOn = (try? await database.isRouteRecordingOn()) ?? routeOn
        isLoaded = true
    }

    /// Band first, then the phone. A change the Loop didn't take puts the control back.
    func setDetection(_ changed: WorkoutDetection) async {
        guard !saving, changed != detection else { return }
        let was = detection
        detection = changed
        saving = true
        failed = nil
        if await !writeDetection(changed) {
            detection = was
            failed = changed
        }
        saving = false
    }

    func tryAgain() async {
        guard let failed else { return }
        await setDetection(failed)
    }

    func setSport(_ sport: WorkoutSport, on: Bool) async {
        let was = sports
        if on { sports.insert(sport) } else { sports.remove(sport) }
        do {
            try await database.setWorkoutSports(sports)
        } catch {
            sports = was
        }
    }

    func setRoute(on: Bool) async {
        let was = routeOn
        routeOn = on
        do {
            try await database.setRouteRecording(on)
        } catch {
            routeOn = was
        }
    }
}
