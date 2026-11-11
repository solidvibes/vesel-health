import Foundation
import Testing
import VeselCore

struct HeadlineTests {
    func status(_ indicator: Int) -> RecoveryStatus {
        RecoveryStatus(NightlyRecharge(night: day("2026-10-26"), recoveryIndicator: indicator, recoveryIndicatorSubLevel: 0))!
    }

    /// Usual sleep 7 h 50 m to 8 h 40 m.
    func sleep(_ state: LineState, _ minutes: Double = 490) -> LineVerdict {
        let explanation = Explanation(method: InRange.method, version: InRange.version, inputs: [], text: "")
        if case .learning = state { return LineVerdict(state: state, explanation: explanation, normal: .none, scale: nil) }
        if state == .none { return LineVerdict(state: .none, explanation: explanation, normal: .none, scale: nil) }
        return LineVerdict(
            state: state, explanation: explanation, normal: LineNormal(low: 470, high: 520),
            scale: LineScale(normalFrom: 0.3, normalTo: 0.7, dot: 0.5, value: minutes))
    }

    /// Usual high stress up to 30 m.
    func calm(_ minutes: Double?) -> LineVerdict {
        InRange.calm(minutes: minutes, previous: Array(repeating: 30, count: 7))
    }

    func lines(_ indicator: Int?, sleep: LineVerdict, calm: LineVerdict, earlierNights: Int = 20) -> DayLines {
        DayLines(recovery: InRange.recovery(status: indicator.map(status), earlierNights: earlierNights), sleep: sleep, calm: calm)
    }

    func make(
        _ indicator: Int?, sleep: LineVerdict, calm: LineVerdict, contributors: [ContributorReading] = [], asleep: Double? = 490, earlierNights: Int = 20,
        yesterdayWorkout: String? = nil
    ) -> Headline? {
        Headline.make(
            lines: lines(indicator, sleep: sleep, calm: calm, earlierNights: earlierNights),
            status: indicator.map(status), contributors: contributors, asleepMinutes: asleep, yesterdayWorkout: yesterdayWorkout
        )
    }

    func workout(_ session: String, load: Double?, rating: Int?) -> Workout {
        Workout(
            session: session, start: at("2026-10-25T17:30:00Z"), end: at("2026-10-25T18:45:00Z"), utcOffsetSeconds: 3600, bandSportId: nil,
            durationSeconds: 4500, calories: nil, cardioLoad: load, cardioLoadRating: rating, trainingLoad: nil, averageHeartRate: nil,
            maxHeartRate: nil, heartRates: nil, fileSize: 1, unreadableFiles: [])
    }

    /// Earlier HRV: mean 42, SD 8.
    var earlierHRV: [DayKey: [Contributor: Double]] { history(.hrv, [30, 34, 38, 42, 46, 50, 54]) }

    @Test func noNightAndNoCalmGivesNoHeadline() {
        #expect(make(nil, sleep: sleep(.none), calm: calm(nil), asleep: nil) == nil)
    }

    @Test func noNightButACalmDaySaysBoth() throws {
        let inside = try #require(make(nil, sleep: sleep(.none), calm: calm(10), asleep: nil))
        #expect(inside.sentence == "No sleep recorded last night.")
        #expect(inside.why == "A calm day so far.")
        let above = try #require(make(nil, sleep: sleep(.none), calm: calm(45), asleep: nil))
        #expect(above.why == "45 m of high stress so far; your usual is up to 30 m.")
    }

    @Test func whileLearningItIsGettingToKnowYou() throws {
        let recovery = try #require(make(5, sleep: sleep(.learning(soFar: 3, of: 7)), calm: calm(10), earlierNights: 3))
        #expect(recovery.sentence == "Getting to know you.")
        #expect(recovery.why == "")
        let sleepOnly = try #require(make(nil, sleep: sleep(.learning(soFar: 3, of: 7)), calm: calm(nil)))
        #expect(sleepOnly.sentence == "Getting to know you.")
    }

    @Test func aNightPolarHasNotScored() throws {
        let headline = try #require(make(nil, sleep: sleep(.inside, 460), calm: calm(10), asleep: 460))
        #expect(headline.sentence == "Polar hasn't scored your recovery yet.")
        #expect(headline.why == "7 h 40 m asleep.")
        #expect(headline.explanation.inputs.first { $0.name == "rule" }?.value == 3)
    }

    @Test func lowerRecoveryNamesTheDriverThenEveryOtherLineOutside() throws {
        // HRV 26 is 2 SDs below its usual 42: 16 ms is 38 % of 42.
        let hrv = readings([.hrv: 26], history: earlierHRV)
        let headline = try #require(make(3, sleep: sleep(.below, 400), calm: calm(45), contributors: hrv))
        #expect(headline.sentence == "Recovery is lower than usual today.")
        #expect(headline.why == "HRV 38 % below your usual. Sleep was also shorter than usual. Stress is also above your normal.")
        #expect(headline.explanation.inputs == [.init(name: "rule", value: 4, unit: "of 9"), .init(name: "recoveryIndicator", value: 3, unit: "of 6")])
    }

    @Test func lowRecovery() throws {
        let headline = try #require(make(2, sleep: sleep(.inside), calm: calm(10)))
        #expect(headline.sentence == "Recovery is low today.")
        #expect(headline.why == "None of last night's readings stood out on its own; Polar weighs them together.")
        let longer = try #require(make(1, sleep: sleep(.above, 600), calm: calm(nil)))
        #expect(longer.why == "Sleep was also longer than usual.")
    }

    @Test func lowRecoveryNamesYesterdaysWorkoutPolarRatedMediumOrHigher() throws {
        let ride = WorkoutLabel(sport: .cycling, source: .band, hidden: false)
        let run = WorkoutLabel(sport: .running, source: .owner, hidden: false)
        // Rated 2: below Polar's middle level, not named.
        #expect(Headline.namedWorkout([(workout("a", load: 182, rating: 2), ride)]) == nil)
        // No rating, however high the load: not named.
        #expect(Headline.namedWorkout([(workout("a", load: 182, rating: nil), ride)]) == nil)
        // Rated 3 and 5: the higher cardio load is named.
        #expect(Headline.namedWorkout([(workout("a", load: 87, rating: 5), run), (workout("b", load: 182, rating: 3), ride)]) == "ride")
        // Hidden ("Not a workout"): not named, the other one is.
        let hidden = WorkoutLabel(sport: .cycling, source: .band, hidden: true)
        #expect(Headline.namedWorkout([(workout("a", load: 87, rating: 3), run), (workout("b", load: 182, rating: 5), hidden)]) == "run")

        let low = try #require(make(2, sleep: sleep(.inside), calm: calm(10), yesterdayWorkout: "ride"))
        #expect(low.sentence == "Low recovery after yesterday's ride.")
        #expect(low.why == "None of last night's readings stood out on its own; Polar weighs them together.")
        #expect(low.explanation.text.contains("It names yesterday's ride: Polar rated its cardio load 3 or higher of 5"))
        let lower = try #require(make(3, sleep: sleep(.inside), calm: calm(10), yesterdayWorkout: "run"))
        #expect(lower.sentence == "Recovery is lower than usual after yesterday's run.")
        // Good recovery never names a workout.
        #expect(try #require(make(5, sleep: sleep(.inside), calm: calm(10), yesterdayWorkout: "ride")).sentence == "Everything looks great today.")
    }

    @Test func shortSleep() throws {
        let headline = try #require(make(5, sleep: sleep(.below, 460), calm: calm(45)))
        #expect(headline.sentence == "You slept less than usual.")
        #expect(headline.why == "7 h 40 m is under your usual of 7 h 50 m to 8 h 40 m. Stress is also above your normal.")
    }

    @Test func longSleep() throws {
        let headline = try #require(make(6, sleep: sleep(.above, 595), calm: calm(10)))
        #expect(headline.sentence == "You slept longer than usual.")
        #expect(headline.why == "9 h 55 m is over your usual of 7 h 50 m to 8 h 40 m; it can mean catching up, or your body asking for rest.")
        #expect(headline.explanation.text == "Sleep is above your normal, so the sentence says you slept longer than usual. The second line gives the numbers.")
    }

    @Test func moreStress() throws {
        let headline = try #require(make(5, sleep: sleep(.inside), calm: calm(45)))
        #expect(headline.sentence == "More stress than usual today.")
        #expect(headline.why == "45 m of high stress so far; your usual is up to 30 m.")
    }

    @Test func aGoodDaySaysSo() throws {
        let good = try #require(make(5, sleep: sleep(.inside), calm: calm(10)))
        #expect(good.sentence == "Everything looks great today.")
        #expect(good.why == "Recovery is good, your sleep was right in your normal, and a calm day so far.")
        #expect(good.explanation.method == "headline")
        #expect(good.explanation.version == 4)
        #expect(good.explanation.inputs.first { $0.name == "rule" }?.value == 9)

        let noSleep = try #require(make(5, sleep: sleep(.none), calm: calm(10)))
        #expect(noSleep.why == "Recovery is good, and a calm day so far.")
        let morning = try #require(make(6, sleep: sleep(.inside), calm: calm(nil)))
        #expect(morning.sentence == "Everything looks great today.")
        #expect(morning.why == "You're well recovered, and your sleep was right in your normal.")
    }

    @Test func anOKNightLooksGood() throws {
        let headline = try #require(make(4, sleep: sleep(.inside), calm: calm(10)))
        #expect(headline.sentence == "Things look good today.")
        #expect(headline.why == "Recovery is OK, your sleep was right in your normal, and a calm day so far.")
    }

    @Test func skinTemperatureInTheWhyFollowsTheUnits() throws {
        // Usual mean 34.2 °C; 34.7 is 0.5 °C above, which is 0.9 °F.
        let skin = readings([.skinTemperature: 34.7], history: history(.skinTemperature, [34.0, 34.2, 34.4, 34.2, 34.0, 34.4, 34.2]))
        let day = lines(3, sleep: sleep(.inside), calm: calm(nil))
        let us = try #require(Headline.make(lines: day, status: status(3), contributors: skin, asleepMinutes: 490, units: .us))
        #expect(us.why == "Skin temperature 0.9 °F above your usual.")
    }
}
