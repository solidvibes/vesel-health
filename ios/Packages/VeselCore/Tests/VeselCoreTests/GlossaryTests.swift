import Testing
@testable import VeselCore

struct GlossaryTests {
    @Test(arguments: Term.allCases) func everyTermStartsWithWhatItIs(term: Term) {
        let meaning = Glossary.meaning(term)
        #expect(meaning.term == term)
        #expect(!meaning.title.isEmpty)
        #expect(meaning.sections.first?.heading == "What it is")
        #expect(meaning.sections.first?.text.isEmpty == false)
    }

    @Test func twentyOneTerms() {
        #expect(Term.allCases.count == 21)
    }

    @Test func goodOrBadIsFoundWhereTheTermHasIt() {
        #expect(Glossary.goodOrBad(.lowestHeartRate) == "Lower than your usual is usually a sign of a restful night.")
    }

    @Test func workoutsSitWithMovement() {
        #expect(Glossary.groups.first { $0.title == "Movement" }?.terms == [.steps, .workout, .cardioLoad])
    }

    @Test func heartGroupHoldsFitnessAndVO2max() {
        let heart = Glossary.groups.first { $0.title == "Heart" }?.terms
        #expect(heart == [.heartRate, .restingHeartRate, .lowestHeartRate, .heartFitness, .vo2max])
    }

    @Test func heartFitnessIsAnEstimateComparedWithYourAge() {
        let meaning = Glossary.meaning(.heartFitness)
        #expect(meaning.sections.map(\.heading) == ["What it is", "Good or bad", "What's normal", "What affects it", "It's an estimate"])
        #expect(meaning.sections.first?.text.contains("resting heart rate while you sleep") == true)
        #expect(Glossary.meaning(.vo2max).sections.last?.heading == "It's an estimate")
    }

    @Test func everyTermIsInExactlyOneGroup() {
        let listed = Glossary.groups.flatMap(\.terms)
        #expect(listed.count == Term.allCases.count)
        #expect(Set(listed) == Set(Term.allCases))
        #expect(Glossary.groups.map(\.title) == ["Sleep", "Recovery", "Heart", "Stress", "Movement", "About the readings"])
    }

    @Test func noTechnicalWordingInTheMeanings() {
        for term in Term.allCases {
            let meaning = Glossary.meaning(term)
            let all = meaning.sections.map(\.text) + [meaning.howTheBandKnows, meaning.workedOut].compactMap { $0 }
            for text in all {
                #expect(!text.contains("Polar's sleep phases spend"))
                #expect(!text.contains("Rule "))
            }
        }
    }

    @Test func titlesAsTheOwnerApproved() {
        #expect(Glossary.meaning(.recovery).title == "Recovery (Polar's Nightly Recharge)")
        #expect(Glossary.meaning(.remSleep).title == "REM sleep")
        #expect(Glossary.meaning(.sleepTime).title == "Sleep time")
    }

    @Test func theStagesCarryTheirShareRule() {
        #expect(Glossary.meaning(.deepSleep).workedOut == "The share is the stage's minutes ÷ your time asleep, rounded.")
        #expect(Glossary.meaning(.awake).workedOut == "The share is the stage's minutes ÷ your time in bed, rounded.")
    }

    @Test func theUsualRangeWordsMatchTheMethod() {
        let meaning = Glossary.meaning(.usualRange)
        #expect(
            meaning.workedOut
                == "The mean ± 1 standard deviation of the previous 28 nights, not counting the night itself, from 7 nights on (method range28, version 1).")
        #expect(
            meaning.sections.first { $0.heading == "What's normal" }?.text == "It needs 7 nights before it shows: \"Your usual range appears after 7 nights\".")
        #expect(meaning.sections.last?.heading == "Why your own")
    }
}
