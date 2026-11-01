import Foundation
import Testing
@testable import Vesel

/// A screen shows "Couldn't show this" only for a real failure, never for a read that was cancelled. A paused database is the
/// other case that never shows it; `PausedTests` (VeselStorage) checks GRDB's own errors for it.
@MainActor
struct ReadProblemTests {
    struct Broken: Error {}

    @Test func aCancelledReadIsNoProblem() async {
        let reads = ReadProblem()
        await reads.observe { throw CancellationError() }
        #expect(!reads.isShown)
    }

    @Test func anyOtherFailureShowsTheCard() async {
        let reads = ReadProblem()
        await reads.observe { throw Broken() }
        #expect(reads.isShown)
    }

    @Test func startingAgainClearsIt() async {
        let reads = ReadProblem()
        await reads.observe { throw Broken() }
        await reads.observe {}
        #expect(!reads.isShown)
    }

    @Test func anotherObservationStartingKeepsIt() async {
        let reads = ReadProblem()
        await reads.observe({ throw Broken() }, observation: "today")
        await reads.observe({}, observation: "steps")
        #expect(reads.isShown)
    }
}
