import Foundation
import Testing
import VeselCore

struct WorkoutLoadTests {
    func workout(cardioLoad: Double?, rating: Int?, trainingLoad: Double?) -> Workout {
        Workout(
            session: "20261103/071000", start: at("2026-11-03T06:10:00Z"), end: at("2026-11-03T06:52:00Z"), utcOffsetSeconds: 3600, bandSportId: 1,
            durationSeconds: 2520, calories: nil, cardioLoad: cardioLoad, cardioLoadRating: rating, trainingLoad: trainingLoad,
            averageHeartRate: nil, maxHeartRate: nil, heartRates: nil, fileSize: 1, unreadableFiles: []
        )
    }

    let band = WorkoutLabel(sport: .running, source: .band, hidden: false)

    @Test func cardioLoadIsTheNumberAndNoWordUntilPolarsIsConfirmed() throws {
        let load = try #require(WorkoutLoad.make(workout(cardioLoad: 172, rating: 4, trainingLoad: 140)))
        #expect(load.number == 172)
        #expect(load.source == .cardioLoad)
        #expect(load.polarWord == nil)
        #expect(PolarLoadWord.confirmed.isEmpty)

        let explanation = WorkoutLoad.explanation(workout(cardioLoad: 172, rating: 4, trainingLoad: 140), label: band, route: nil)
        #expect(explanation.method == "workout")
        #expect(explanation.version == 1)
        #expect(explanation.inputs.map(\.name) == ["cardioLoad", "cardioLoadRating"])
        #expect(
            explanation.text
                == "Cardio load 172 is Polar's own number for this workout, from your heart rate and its length, as the Loop gave it. Polar rated it 4 of 5, comparing it with your last 90 days. The Loop gave the sport."
        )
    }

    @Test func trainingLoadIsTheFallbackOnlyWithoutACardioLoad() throws {
        let load = try #require(WorkoutLoad.make(workout(cardioLoad: nil, rating: nil, trainingLoad: 140)))
        #expect(load.number == 140)
        #expect(load.source == .trainingLoad)
        #expect(load.polarWord == nil)
        #expect(WorkoutLoad.make(workout(cardioLoad: nil, rating: 3, trainingLoad: nil)) == nil)
    }

    @Test func aGuessFromSpeedSaysTheSpeedAndTheRouteCoverage() {
        let workout = workout(cardioLoad: 87, rating: nil, trainingLoad: nil)
        let points = (0...42).map {
            RoutePoint(time: workout.start.addingTimeInterval(Double($0 * 60)), latitude: 52.5 + 0.002 * Double($0), longitude: 13.4, accuracy: 5)
        }
        let route = WorkoutRouteSummary(points: points, workout: workout.interval, durationSeconds: 2520)
        let explanation = WorkoutLoad.explanation(workout, label: WorkoutLabel(sport: .cycling, source: .speed, hidden: false), route: route)
        #expect(explanation.inputs.first { $0.name == "routeCoverage" }?.value == 1)
        #expect(explanation.text.hasSuffix("The sport is guessed from speed: 13.3 km/h over a route covering 100 % of the workout (over 13 km/h is cycling, else running)."))
    }
}
