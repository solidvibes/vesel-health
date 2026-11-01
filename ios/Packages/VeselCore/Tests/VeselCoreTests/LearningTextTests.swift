import Testing
@testable import VeselCore

struct LearningTextTests {
    @Test func nightsAndDaysCountTheEarlierOnes() {
        #expect(LearningText.nights(3) == "Your usual range appears after 7 nights · 3 of 7")
        #expect(LearningText.nights(0) == "Your usual range appears after 7 nights")
        #expect(LearningText.days(4) == "Your stress levels appear after 7 days · 4 of 7")
        #expect(LearningText.days(0) == "Your stress levels appear after 7 days")
    }

    @Test func fitnessNamesTheNextFirstOfTheMonth() {
        #expect(
            LearningText.fitness(next: DayKey("2026-12-01")!)
                == "Heart fitness is worked out on the 1st of each month, once a month has 7 nights and 14 days with your Loop. Next: 1 Dec.")
    }
}
