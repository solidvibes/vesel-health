import Foundation
import Testing
import VeselCore
@testable import Vesel

struct MeaningTests {
    @Test(arguments: Term.allCases) func aTermLinkOpensItsOwnTerm(term: Term) {
        #expect(TermLink.term(of: TermLink.url(term)) == term)
    }

    @Test func otherLinksAreNotTermLinks() throws {
        #expect(TermLink.term(of: try #require(URL(string: "https://example.com"))) == nil)
        #expect(TermLink.term(of: try #require(URL(string: "vesel-term:nothing"))) == nil)
    }

    @Test func theLearningWordingLinksTheUsualRange() {
        let text = TermLink.text("Your usual range appears after 7 nights · 3 of 7", linking: "usual range", to: .usualRange)
        let linked = text.runs.filter { $0.link != nil }.map { String(text[$0.range].characters) }
        #expect(linked == ["usual range"])
    }

    @Test func aMissingPhraseLeavesTheTextAlone() {
        let text = TermLink.text("Your stress levels appear after 7 days", linking: "usual range", to: .usualRange)
        #expect(text.runs.allSatisfy { $0.link == nil })
    }

    @Test func yoursWordsTheValueAgainstTheUsual() {
        let range = PersonalRange(mean: 43, sd: 9, nights: 28)
        let text: (Double) -> String = { "\(Int($0)) ms" }
        #expect(YoursText.vsUsual(value: 48, range: range, nights: 28, text: text) == "within your usual (34–52 ms)")
        #expect(YoursText.vsUsual(value: 60, range: range, nights: 28, text: text) == "higher than your usual (34–52 ms)")
        #expect(YoursText.vsUsual(value: 20, range: range, nights: 28, text: text) == "much lower than your usual (34–52 ms)")
        #expect(YoursText.vsUsual(value: 48, range: nil, nights: 3, text: text) == "Your usual range appears after 7 nights · 3 of 7")
    }

    @Test func timesAreWrittenOutInTheRange() {
        let range = PersonalRange(mean: 445, sd: 25, nights: 28)
        #expect(YoursText.vsUsual(value: 425, range: range, nights: 28, text: { DurationText.hoursMinutes(minutes: $0) }) == "within your usual (7 h–7 h 50 m)")
    }

    private func sleep(_ asleep: Double, mean: Double, sd: Double) throws -> ContributorReading {
        let inputs: [Explanation.Input] = [
            .init(name: "value", value: asleep, unit: "min"), .init(name: "nights", value: 26, unit: "nights"),
            .init(name: "usualMean", value: mean, unit: "min"), .init(name: "usualSD", value: sd, unit: "min"),
        ]
        return try #require(
            ContributorReading(
                ComputedMetric(
                    kind: Contributor.sleep.kind, day: DayKey(year: 2026, month: 10, day: 26), hour: nil, value: asleep, unit: "min",
                    explanation: Explanation(method: RecoveryContributors.method, version: RecoveryContributors.version, inputs: inputs, text: ""),
                    computedAt: Date(timeIntervalSince1970: 0)
                )))
    }

    @Test func theSleepYoursLineQuotesTheSleepLinesNormal() throws {
        let inside = try sleep(500, mean: 440, sd: 35)
        let line = InRange.sleep(inside)
        #expect(line.state == .inside)
        #expect(line.normal == LineNormal(low: 405, high: 510))
        #expect(YoursText.contributor(inside, when: "Last night") == "Last night: 8 h 20 m asleep, within your normal (6 h 45 m–8 h 30 m).")
        #expect(
            YoursText.contributor(try sleep(380, mean: 440, sd: 35), when: "Last night")
                == "Last night: 6 h 20 m asleep, shorter than your normal (6 h 45 m–8 h 30 m).")
        #expect(
            YoursText.contributor(try sleep(560, mean: 440, sd: 35), when: "Last night")
                == "Last night: 9 h 20 m asleep, longer than your normal (6 h 45 m–8 h 30 m).")
    }
}
