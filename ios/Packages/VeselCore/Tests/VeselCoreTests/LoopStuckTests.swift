import Foundation
import Testing
@testable import VeselCore

struct LoopStuckTests {
    let now = at("2026-11-08T09:00:00Z")

    func run(_ minutesAgo: Double, _ outcome: SyncOutcome?, _ detail: String? = nil) -> SyncRun {
        let start = now.addingTimeInterval(-minutesAgo * 60)
        return SyncRun(
            id: 1, trigger: .bandCheckIn, startedAt: start, finishedAt: outcome == nil ? nil : start.addingTimeInterval(3), outcome: outcome,
            detail: detail)
    }

    func busy(_ minutesAgo: Double) -> SyncRun { run(minutesAgo, .failed, "Loop busy at dailySummary") }

    @Test func busyForTwoHoursIsStuckSinceTheFirstBusyRead() {
        #expect(LoopStuck.since([busy(5), busy(60), busy(125), run(200, .success)], now: now) == now.addingTimeInterval(-125 * 60))
    }

    /// A workout keeps the Loop busy for a while: not stuck before two hours.
    @Test func busyForLessThanTwoHoursIsNotStuck() {
        #expect(LoopStuck.since([busy(5), busy(100), run(130, .success)], now: now) == nil)
    }

    @Test func aReadThatGotThroughEndsIt() {
        #expect(LoopStuck.since([run(2, .success), busy(60), busy(180)], now: now) == nil)
        #expect(LoopStuck.since([run(2, .failed, "Sync stopped at fetch: other"), busy(180)], now: now) == nil)
    }

    @Test func readsThatNeverReachedTheLoopDontCount() {
        #expect(LoopStuck.since([run(1, .unreachable, "Band not nearby"), run(3, nil), busy(10), busy(150)], now: now) == now.addingTimeInterval(-150 * 60))
        #expect(LoopStuck.since([run(1, .unreachable, "Band not nearby"), run(300, nil)], now: now) == nil)
    }

    @Test func aBusyReadReadsAsLoopBusy() {
        #expect(SyncRunWords.outcome(busy(1)) == "Loop busy")
    }
}
