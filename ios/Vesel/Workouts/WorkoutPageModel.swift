import Foundation
import Observation
import VeselCore
import VeselStorage

/// One workout for its page: the workout with its label, route and load (worked out in VeselCore on read), and the owner's fix.
@MainActor
@Observable
final class WorkoutPageModel {
    private(set) var detail: WorkoutDetail?
    private(set) var isLoaded = false
    /// The owner said "Not a workout": the page goes back.
    private(set) var isClosed = false
    let session: String
    private let reads = ReadProblem()
    private let database: AppDatabase
    private let clock: any VeselClock
    private let unitsStore: UnitsStore
    private let recomputeStress: (Set<DayKey>) async -> Void

    /// `recomputeStress` works out the stress of those days again at once, so a fix shows there straight away.
    init(
        database: AppDatabase, clock: any VeselClock, units: UnitsStore, session: String,
        recomputeStress: @escaping (Set<DayKey>) async -> Void
    ) {
        self.database = database
        self.clock = clock
        unitsStore = units
        self.session = session
        self.recomputeStress = recomputeStress
    }

    var zone: TimeZone { clock.timeZone }
    var readProblem: Bool { reads.isShown }
    var labelled: LabelledWorkout? { detail?.labelled }
    var workout: Workout? { labelled?.workout }
    var label: WorkoutLabel? { labelled?.label }

    /// "guessed from speed · change"; nil when the Loop or the owner named the sport, or nothing could be guessed.
    var guessChip: String? {
        switch label?.source {
        case .speed: "guessed from speed · change"
        case .timeOfDay: "guessed from time of day · change"
        default: nil
        }
    }

    /// "Sun, Oct 25 · 07:10–07:52"
    var dateLine: String? {
        guard let workout else { return nil }
        let day = DayKey(workout.start, in: zone)
        return "\(Formatters.day(day, zone: zone)) · \(Formatters.clock(workout.start, zone: zone))–\(Formatters.clock(workout.end, zone: zone))"
    }

    /// The route's kept points, when there are enough to draw a line.
    var routePoints: [RoutePoint] {
        guard let points = labelled?.route?.points, points.count >= 2 else { return [] }
        return points
    }

    /// "8.4 km · 11.9 km/h average", or "8.4 km · Route covers 12 of 42 min" when it covers less than half the workout.
    var routeLine: String? {
        guard let route = labelled?.route, routePoints.count >= 2, let workout else { return nil }
        let units = unitsStore.units
        let distance = units.distanceText(meters: route.distanceMeters)
        if route.coversEnough, let speed = route.averageSpeedKmh {
            return "\(distance) · \(units.speedText(kmh: speed)) average"
        }
        let covered = Int((route.coveredSeconds / 60).rounded())
        let total = Int((Double(workout.durationSeconds) / 60).rounded())
        return "\(distance) · Route covers \(covered) of \(total) min"
    }

    /// The Loop's heart rate during the workout; the 24/7 readings in its window when the workout file had none.
    var heartPoints: [ReadingPoint] {
        guard let detail else { return [] }
        let workout = detail.labelled.workout
        if let averaged = workout.heartRates?.averaged() {
            return averaged.points.map { ReadingPoint(time: workout.start.addingTimeInterval($0.offsetSeconds), value: $0.bpm) }
        }
        return detail.dayHeartRates.map { ReadingPoint(time: $0.time, value: Double($0.bpm)) }
    }

    var load: WorkoutLoad? { labelled?.load }

    /// The meaning sheet's line for this workout: "This workout: cardio load 172, rated 4 of 5 by Polar."
    var loadYours: String? {
        guard let load else { return nil }
        let rating = load.source == .cardioLoad ? workout?.cardioLoadRating.map { ", rated \($0) of 5 by Polar" } ?? "" : ""
        return "This workout: \(load.spokenText)\(rating)."
    }

    var explanation: Explanation? {
        guard let labelled else { return nil }
        return WorkoutLoad.explanation(labelled.workout, label: labelled.label, route: labelled.route)
    }

    /// The sport sheet's choices: the owner's sports, and the one shown now if it isn't among them.
    var sheetSports: [WorkoutSport] {
        let sports = detail?.sports ?? []
        return WorkoutSport.allCases.filter { sports.contains($0) || $0 == label?.sport }
    }

    var isSwim: Bool { label?.sport == .swimming }

    func observe() async {
        await reads.observe {
            for try await value in database.observeWorkout(session: session) {
                detail = value
                isLoaded = true
            }
        }
    }

    /// The owner's sport. Kept apart from the band's row, so a later read never replaces it.
    func choose(_ sport: WorkoutSport) async {
        await save(WorkoutChoice(session: session, sport: sport, hidden: false, chosenAt: clock.now))
    }

    /// Hides the workout everywhere; its time counts for stress again, worked out at once.
    func notAWorkout() async {
        if await save(WorkoutChoice(session: session, sport: nil, hidden: true, chosenAt: clock.now)) { isClosed = true }
    }

    @discardableResult
    private func save(_ choice: WorkoutChoice) async -> Bool {
        guard let workout else { return false }
        do {
            try await database.setChoice(choice)
        } catch {
            return false
        }
        await recomputeStress([DayKey(workout.start, in: zone), DayKey(workout.end, in: zone)])
        return true
    }
}
