import Foundation
import Testing
import VeselCore

struct TodayStateTests {
    let today = day("2026-10-26")

    /// After the morning window unless a test says otherwise.
    func state(
        _ sync: SyncStatus = .idle,
        asleep: Bool = false,
        finishing: Bool = false,
        endedAt: String? = nil,
        dismissed: Bool = false,
        tappedAt: String? = nil,
        missedLoop: Bool = false,
        latest: String? = "2026-10-26",
        now: String = "2026-10-26T14:00:00Z",
        earlier: Int = 20,
        alerts: Int = 0
    ) -> TodayState {
        TodayState(
            sync: sync, bandStillRecordingSleep: asleep, bandFinishingNight: finishing, sleepEndedAt: endedAt.map(at),
            dismissedGoodMorning: dismissed, imUp: tappedAt.map { ImUpRequest(tappedAt: at($0), missedLoop: missedLoop) },
            latestNight: latest.map(day), today: today, now: at(now), timeZone: .gmt, earlierNights: earlier, alertsToday: alerts
        )
    }

    @Test func somethingIsOffWhenAnAlertWentOutTodayWhateverTheBodyShows() {
        #expect(!state().somethingOff)
        #expect(state(alerts: 1).somethingOff)
        #expect(state(alerts: 1).body == .normal)
        #expect(state(.unreachable(lastRead: nil), alerts: 2).somethingOff)
    }

    @Test func normalWhenLastNightIsInAndThereIsAHistory() {
        #expect(state().body == .normal)
        #expect(state().morningCard == .none)
        #expect(!state().lastNightMissing)
    }

    @Test func firstDayUntilSevenEarlierNights() {
        #expect(state(earlier: 0).body == .firstDay(nights: 0))
        #expect(state(earlier: 6).body == .firstDay(nights: 6))
        #expect(state(earlier: 7).body == .normal)
    }

    @Test func readingShowsSkeletonsOnlyWhileThereIsNothingForLastNight() {
        #expect(state(.reading(SyncProgress()), latest: nil).body == .reading)
        #expect(state(.reading(SyncProgress()), latest: "2026-10-25").body == .reading)
        #expect(state(.reading(SyncProgress()), latest: "2026-10-26").body == .normal)
    }

    @Test func unreachableKeepsTheLastNumbersBelow() {
        let lastRead = at("2026-10-26T05:00:00Z")
        #expect(state(.unreachable(lastRead: lastRead)).body == .unreachable(lastRead: lastRead))
        #expect(state(.unreachable(lastRead: nil), latest: nil).body == .unreachable(lastRead: nil))
    }

    @Test func aBandWithNoNightYetHasNoSleep() {
        #expect(state(latest: nil).body == .noSleep)
    }

    @Test func goodMorningShowsWhileTheBandStillRecordsUntilDismissed() {
        #expect(state(asleep: true, latest: "2026-10-25").morningCard == .goodMorning)
        #expect(state(asleep: true, dismissed: true, latest: "2026-10-25").morningCard == .none)
        #expect(state(asleep: false, latest: "2026-10-25").morningCard == .none)
        #expect(state(asleep: true, latest: "2026-10-25").lastNightMissing)
        #expect(state(asleep: true, latest: "2026-10-25").body == .normal)
    }

    /// The band said "can't say" (passed as still recording), is finishing, is being read, or a tap waits: once last
    /// night is stored the morning is over.
    @Test func aStoredNightEndsTheMorningWhateverTheBandSays() {
        #expect(state(asleep: true).morningCard == .none)
        #expect(state(finishing: true).morningCard == .none)
        #expect(state(.reading(SyncProgress())).morningCard == .none)
        #expect(state(tappedAt: "2026-10-26T13:00:00Z").morningCard == .none)
        #expect(state(asleep: true, now: "2026-10-26T07:00:00Z").morningCard == .none)
    }

    @Test func aWaitingTapShowsEvaluatingUntilSixHoursHavePassed() {
        let latest = "2026-10-25"
        #expect(state(asleep: true, tappedAt: "2026-10-26T13:00:00Z", latest: latest).morningCard == .evaluating(waitingForLoop: false))
        #expect(state(asleep: true, tappedAt: "2026-10-26T13:00:00Z", missedLoop: true, latest: latest).morningCard == .evaluating(waitingForLoop: true))
        #expect(state(asleep: true, tappedAt: "2026-10-26T08:00:00Z", latest: latest).morningCard == .goodMorning)
        #expect(state(tappedAt: "2026-10-26T08:00:00Z", latest: latest).morningCard == .none)
        // A tap time in the future (the clock went back) isn't waiting.
        #expect(state(asleep: true, tappedAt: "2026-10-26T15:00:00Z", latest: latest).morningCard == .goodMorning)
    }

    @Test func aWaitingTapKeepsLastNightPendingLongAfterTheBandStopped() {
        let waiting = state(tappedAt: "2026-10-26T13:00:00Z", latest: "2026-10-25")
        #expect(waiting.lastNightPending)
        #expect(!state(latest: "2026-10-25").lastNightPending)
    }

    @Test func withNoNightAtAllAWaitingTapStillShowsEvaluating() {
        #expect(state(tappedAt: "2026-10-26T13:00:00Z", latest: nil).morningCard == .evaluating(waitingForLoop: false))
        #expect(state(asleep: true, latest: nil).morningCard == .goodMorning)
    }

    @Test func theLoopEndingTheNightShowsEvaluatingWhilePolarFinishes() {
        #expect(state(finishing: true, latest: "2026-10-25").morningCard == .evaluating(waitingForLoop: false))
        #expect(state(.reading(SyncProgress()), latest: "2026-10-25").morningCard == .evaluating(waitingForLoop: false))
    }

    /// 31 October: the Loop was out of reach all night, so nothing said it still recorded. "I'm up" shows 03:00–12:00.
    @Test func goodMorningShowsFromThreeUntilNoonWithoutTheLoop() {
        let latest = "2026-10-25"
        #expect(state(latest: latest, now: "2026-10-26T03:00:00Z").morningCard == .goodMorning)
        #expect(state(latest: latest, now: "2026-10-26T11:59:00Z").morningCard == .goodMorning)
        #expect(state(latest: latest, now: "2026-10-26T02:59:00Z").morningCard == .none)
        #expect(state(latest: latest, now: "2026-10-26T12:00:00Z").morningCard == .none)
        #expect(state(latest: nil, now: "2026-10-26T08:00:00Z").morningCard == .goodMorning)
        #expect(state(dismissed: true, latest: latest, now: "2026-10-26T08:00:00Z").morningCard == .none)
    }

    @Test func aNightTheLoopStoppedTodayEndsTheMorningWindow() {
        let latest = "2026-10-25"
        #expect(state(endedAt: "2026-10-26T06:30:00Z", latest: latest, now: "2026-10-26T09:00:00Z").morningCard == .none)
        #expect(
            state(finishing: true, endedAt: "2026-10-26T08:30:00Z", latest: latest, now: "2026-10-26T09:00:00Z").morningCard
                == .evaluating(waitingForLoop: false))
        #expect(state(endedAt: "2026-10-25T07:00:00Z", latest: latest, now: "2026-10-26T09:00:00Z").morningCard == .goodMorning)
    }

    @Test func waitingForTheLoopKeepsTheNumbers() {
        #expect(state(.waitingForLoop).body == .waitingForLoop)
    }

    @Test func lastNightIsPendingWhileTheBandRecordsItOrItIsBeingRead() {
        #expect(state(asleep: true, latest: "2026-10-25").lastNightPending)
        #expect(state(.reading(SyncProgress()), latest: "2026-10-25").lastNightPending)
        #expect(state(finishing: true, latest: "2026-10-25").lastNightPending)
        #expect(!state(latest: "2026-10-25").lastNightPending)
        #expect(!state(asleep: true).lastNightPending)
        #expect(!state(asleep: true, latest: nil).lastNightPending)
    }
}
