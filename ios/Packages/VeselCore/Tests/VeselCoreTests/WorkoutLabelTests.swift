import Foundation
import Testing
import VeselCore

struct WorkoutLabelTests {
    let all = Set(WorkoutSport.allCases)

    /// 07:10 in Berlin on Nov 3, 42 minutes.
    func workout(sport: Int? = nil, start: String = "2026-11-03T06:10:00Z") -> Workout {
        let begin = at(start)
        return Workout(
            session: "20261103/071000", start: begin, end: begin.addingTimeInterval(2520), utcOffsetSeconds: 3600, bandSportId: sport,
            durationSeconds: 2520, calories: nil, cardioLoad: 87, cardioLoadRating: nil, trainingLoad: nil, averageHeartRate: nil,
            maxHeartRate: nil, heartRates: nil, fileSize: 1, unreadableFiles: []
        )
    }

    /// A straight route north over the whole workout at the given speed, one point a minute.
    func route(kmh: Double, minutes: Int = 42) -> WorkoutRouteSummary {
        let w = workout()
        let metersPerMinute = kmh / 3.6 * 60
        let degreesPerMinute = metersPerMinute / (6_371_008.8 * .pi / 180)
        let points = (0...minutes).map {
            RoutePoint(time: w.start.addingTimeInterval(Double($0 * 60)), latitude: 52.5 + degreesPerMinute * Double($0), longitude: 13.4, accuracy: 5)
        }
        return WorkoutRouteSummary(points: points, workout: w.interval, durationSeconds: w.durationSeconds)
    }

    func label(
        _ workout: Workout, choice: WorkoutChoice? = nil, route: WorkoutRouteSummary? = nil, history: [(start: Date, sport: WorkoutSport)] = [],
        sports: Set<WorkoutSport>? = nil
    ) -> WorkoutLabel {
        WorkoutLabel.make(workout: workout, choice: choice, route: route, history: history, sports: sports ?? all, zone: berlin)
    }

    @Test func theOwnersFixComesFirstAndIsKeptHidden() {
        let choice = WorkoutChoice(session: "20261103/071000", sport: .swimming, hidden: false, chosenAt: .distantPast)
        #expect(label(workout(sport: 2), choice: choice, route: route(kmh: 25)) == WorkoutLabel(sport: .swimming, source: .owner, hidden: false))
        let hidden = WorkoutChoice(session: "20261103/071000", sport: nil, hidden: true, chosenAt: .distantPast)
        #expect(label(workout(sport: 2), choice: hidden) == WorkoutLabel(sport: .cycling, source: .band, hidden: true))
    }

    /// The Loop's sport shows even when it isn't one of your sports.
    @Test func theLoopsSportComesNext() {
        #expect(label(workout(sport: 1), route: route(kmh: 25), sports: [.cycling]) == WorkoutLabel(sport: .running, source: .band, hidden: false))
        // Other ids aren't known yet: no band sport.
        #expect(label(workout(sport: 16)).source == .none)
    }

    @Test func speedOverAtLeastHalfTheWorkoutGuessesRideOrRun() {
        #expect(label(workout(), route: route(kmh: 13.5)) == WorkoutLabel(sport: .cycling, source: .speed, hidden: false))
        #expect(label(workout(), route: route(kmh: 12.5)) == WorkoutLabel(sport: .running, source: .speed, hidden: false))
        // 20 of 42 minutes is under half: no guess from speed.
        #expect(label(workout(), route: route(kmh: 25, minutes: 20)).source == .none)
        // Cycling isn't one of your sports: speed can't name it, so time of day decides.
        #expect(label(workout(), route: route(kmh: 25), sports: [.running, .swimming]).source == .none)
    }

    /// The most frequent sport within 2 hours of 07:10 local over the 90 days before; ties in the order cycling, running, swimming, strength.
    @Test func timeOfDayGuessesFromYourOwnWeeks() {
        let history: [(start: Date, sport: WorkoutSport)] = [
            (at("2026-10-01T05:30:00Z"), .running),  // 07:30 local (UTC+2): in
            (at("2026-10-08T07:05:00Z"), .running),  // 09:05 local: 1 h 55 m later, in
            (at("2026-10-15T07:20:00Z"), .cycling),  // 09:20 local: 2 h 10 m later, out
            (at("2026-07-20T05:10:00Z"), .cycling),  // more than 90 days before: out
            (at("2026-10-20T05:00:00Z"), .cycling),  // 07:00 local: in
        ]
        #expect(label(workout(), history: history) == WorkoutLabel(sport: .running, source: .timeOfDay, hidden: false))
        // Without running among your sports, cycling is the only one left.
        #expect(label(workout(), history: history, sports: [.cycling, .swimming]).sport == .cycling)
        // One each: the tie goes to cycling.
        let tie: [(start: Date, sport: WorkoutSport)] = [(at("2026-10-01T05:30:00Z"), .running), (at("2026-10-20T05:00:00Z"), .cycling)]
        #expect(label(workout(), history: tie).sport == .cycling)
    }

    @Test func nothingToGoOnIsAWorkout() {
        #expect(label(workout()) == WorkoutLabel(sport: nil, source: .none, hidden: false))
    }
}
