import Testing
@testable import VeselCore

struct HourlyStepsTests {
    let day = DayKey("2026-10-26")!

    func sample(_ time: String, _ steps: Int) -> HourlySteps.Sample {
        .init(time: "2026-10-26T\(time)+01:00", steps: steps)
    }

    @Test func minutesAreSummedIntoTheirWallClockHour() {
        let hourly = HourlySteps(
            day: day,
            samples: [
                sample("07:59:00", 10), sample("08:00:00", 20), sample("08:30:00", 15), sample("08:59:00", 5), sample("14:01:00", 40),
            ])
        #expect(hourly.hours == [.init(hour: 7, steps: 10), .init(hour: 8, steps: 40), .init(hour: 14, steps: 40)])
    }

    @Test func hoursWithNoStepsHaveNoBar() {
        let hourly = HourlySteps(day: day, samples: [sample("03:00:00", 0), sample("09:00:00", 12)])
        #expect(hourly.hours.map(\.hour) == [9])
    }

    @Test func noSamplesIsEmpty() {
        #expect(HourlySteps(day: day, samples: []).isEmpty)
    }

    @Test func theHourThatRepeatsWhenClocksGoBackIsOneBar() {
        let back = DayKey("2026-10-25")!
        let hourly = HourlySteps(
            day: back,
            samples: [
                .init(time: "2026-10-25T01:30:00+02:00", steps: 30),
                .init(time: "2026-10-25T01:30:00+01:00", steps: 20),
                .init(time: "2026-10-25T02:10:00+01:00", steps: 7),
            ])
        #expect(hourly.hours == [.init(hour: 1, steps: 50), .init(hour: 2, steps: 7)])
    }

    @Test func theHourSkippedWhenClocksGoForwardHasNoBar() {
        let forward = DayKey("2026-03-29")!
        let hourly = HourlySteps(
            day: forward,
            samples: [
                .init(time: "2026-03-29T01:59:00+01:00", steps: 3),
                .init(time: "2026-03-29T03:00:00+02:00", steps: 9),
            ])
        #expect(hourly.hours.map(\.hour) == [1, 3])
    }

    @Test func samplesDatedAnotherDayAreLeftOut() {
        let hourly = HourlySteps(
            day: day,
            samples: [
                .init(time: "2026-10-25T23:59:00+01:00", steps: 99), sample("00:00:00", 4),
            ])
        #expect(hourly.hours == [.init(hour: 0, steps: 4)])
    }
}
