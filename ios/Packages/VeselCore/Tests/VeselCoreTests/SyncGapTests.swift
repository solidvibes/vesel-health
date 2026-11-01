import Foundation
import Testing
import VeselCore

struct SyncGapTests {
    let now = at("2026-10-26T09:00:00Z")

    func isDue(_ trigger: SyncTrigger, started: String?, finished: String?, nightOver: Bool = true) -> Bool {
        let runs = started.map { [SyncRun(id: 1, trigger: .manual, startedAt: at($0), finishedAt: nil, outcome: nil, detail: nil)] } ?? []
        return SyncGap.isDue(trigger: trigger, now: now, runs: runs, lastFinishedAt: finished.map(at), nightOver: nightOver)
    }

    /// Open, close (the read is cut off), open again: the second open reads.
    @Test func openingAfterACutOffReadReads() {
        #expect(isDue(.foreground, started: "2026-10-26T08:58:00Z", finished: "2026-10-26T07:00:00Z"))
    }

    @Test func openingRightAfterAFinishedReadWaitsOnceTheNightIsOver() {
        #expect(!isDue(.foreground, started: "2026-10-26T08:57:00Z", finished: "2026-10-26T08:58:00Z"))
        #expect(isDue(.foreground, started: "2026-10-26T08:57:00Z", finished: "2026-10-26T08:58:00Z", nightOver: false))
        #expect(isDue(.foreground, started: "2026-10-26T08:54:00Z", finished: "2026-10-26T08:55:00Z"))
    }

    @Test func automaticTriggersWaitAfterAnyRecentStart() {
        #expect(!isDue(.bandEvent, started: "2026-10-26T08:58:00Z", finished: nil, nightOver: false))
        #expect(isDue(.bandEvent, started: "2026-10-26T08:54:00Z", finished: nil))
        #expect(isDue(.bandEvent, started: nil, finished: nil))
    }

    @Test func aTimeInTheFutureIsNotRecent() {
        #expect(isDue(.bandEvent, started: "2026-10-26T10:00:00Z", finished: nil))
        #expect(isDue(.foreground, started: "2026-10-26T10:00:00Z", finished: "2026-10-26T10:01:00Z"))
    }

    /// The Loop was away at 08:58: when it connects at 09:00 it reads; a read that reached it at 08:57 still holds it back.
    @Test func triesThatNeverFoundTheLoopDontHoldBackTheNext() {
        let away = SyncRun(
            id: 2, trigger: .bandCheckIn, startedAt: at("2026-10-26T08:58:00Z"), finishedAt: at("2026-10-26T08:58:20Z"), outcome: .unreachable,
            detail: SyncDetail.notNearby)
        let reached = SyncRun(id: 1, trigger: .manual, startedAt: at("2026-10-26T08:57:00Z"), finishedAt: nil, outcome: nil, detail: nil)
        let earlier = SyncRun(
            id: 1, trigger: .manual, startedAt: at("2026-10-26T08:40:00Z"), finishedAt: at("2026-10-26T08:41:00Z"), outcome: .success, detail: nil)
        #expect(SyncGap.isDue(trigger: .bandEvent, now: now, runs: [away, earlier], lastFinishedAt: nil, nightOver: true))
        #expect(!SyncGap.isDue(trigger: .bandEvent, now: now, runs: [away, reached], lastFinishedAt: nil, nightOver: true))
    }

    /// A check-in that couldn't read at 08:58 holds back the next check-in, but not the Loop reconnecting.
    @Test func checkInsWaitAfterAFailedCheckIn() {
        let failed = SyncRun(
            id: 2, trigger: .bandCheckIn, startedAt: at("2026-10-26T08:58:00Z"), finishedAt: at("2026-10-26T08:58:20Z"), outcome: .unreachable,
            detail: SyncDetail.notNearby)
        let older = SyncRun(
            id: 1, trigger: .bandCheckIn, startedAt: at("2026-10-26T08:54:00Z"), finishedAt: at("2026-10-26T08:54:20Z"), outcome: .unreachable,
            detail: SyncDetail.notNearby)
        #expect(!SyncGap.isDue(trigger: .bandCheckIn, now: now, runs: [failed], lastFinishedAt: nil, nightOver: true))
        #expect(SyncGap.isDue(trigger: .bandEvent, now: now, runs: [failed], lastFinishedAt: nil, nightOver: true))
        #expect(SyncGap.isDue(trigger: .bandCheckIn, now: now, runs: [older], lastFinishedAt: nil, nightOver: true))
    }
}
