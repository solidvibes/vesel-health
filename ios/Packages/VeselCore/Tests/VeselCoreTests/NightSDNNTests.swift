import Foundation
import Testing
@testable import VeselCore

/// The sample night runs 21:30 to 05:30 UTC.
struct NightSDNNTests {
    /// `count` beats alternating 1000 ms and 1000 + d ms. With 60 beats the mean is 1000 + d/2 and every beat is d/2 off it,
    /// so SDNN = √(60 × (d/2)² ÷ 59) = d × 0.504219…: 40.3376 ms for d = 80.
    func session(_ iso: String, spread: Int, beats count: Int = 60, flaggedFrom: Int? = nil) -> PPISession {
        let start = at(iso)
        var elapsed = 0
        let samples = (0..<count).map { index -> PPISample in
            let interval = index % 2 == 0 ? 1000 : 1000 + spread
            elapsed += interval
            return PPISample(
                time: start.addingTimeInterval(Double(elapsed) / 1000), intervalMs: interval, errorMs: 5,
                blocker: flaggedFrom.map { index >= $0 } ?? false, skinContact: true)
        }
        return PPISession(start: start, trigger: .automatic, utcOffsetSeconds: 3600, samples: samples)
    }

    var fiveInside: [PPISession] {
        [
            session("2026-10-25T23:00:00Z", spread: 40), session("2026-10-26T00:00:00Z", spread: 60),
            session("2026-10-26T01:00:00Z", spread: 80), session("2026-10-26T02:00:00Z", spread: 100),
            session("2026-10-26T03:00:00Z", spread: 120),
        ]
    }

    @Test func theNightIsTheMiddleRecordingsSDNN() throws {
        let metric = try #require(NightSDNN.metric(sleep: sampleNight(), sessions: fiveInside, computedAt: at("2026-10-26T06:00:00Z")))

        #expect(abs(metric.value - 40.33755872716886) < 1e-9)
        #expect(metric.kind == "heart.sdnn")
        #expect(metric.day == day("2026-10-26"))
        #expect(metric.unit == "ms")
        #expect(metric.explanation.method == "sdnn")
        #expect(metric.explanation.inputs.map(\.value) == [5, 5, 300])
    }

    /// A recording that started before sleep, and one with a quarter of its beats flagged (60 clean, but only 75 % kept),
    /// don't count. Counted, the d = 200 one would move the middle to d = 90.
    @Test func recordingsCrossingSleepOrMostlyFlaggedDontCount() throws {
        let sessions =
            fiveInside + [
                session("2026-10-25T21:29:30Z", spread: 200),
                session("2026-10-26T04:00:00Z", spread: 200, beats: 80, flaggedFrom: 60),
            ]

        let metric = try #require(NightSDNN.metric(sleep: sampleNight(), sessions: sessions, computedAt: at("2026-10-26T06:00:00Z")))

        #expect(abs(metric.value - 40.33755872716886) < 1e-9)
        #expect(metric.explanation.inputs.map(\.value) == [5, 6, 300])
    }

    @Test func fourRecordingsAreTooFew() {
        #expect(NightSDNN.metric(sleep: sampleNight(), sessions: Array(fiveInside.prefix(4)), computedAt: at("2026-10-26T06:00:00Z")) == nil)
        #expect(
            NightSDNN.metric(
                sleep: sampleNight(), sessions: Array(fiveInside.prefix(4)) + [session("2026-10-26T04:00:00Z", spread: 80, beats: 59)],
                computedAt: at("2026-10-26T06:00:00Z")) == nil)
    }
}
