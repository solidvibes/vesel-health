import Foundation
import Testing
@testable import VeselCore

struct SyncRunWordsTests {
    func run(_ outcome: SyncOutcome?, _ detail: String? = nil) -> SyncRun {
        SyncRun(
            id: 1, trigger: .manual, startedAt: at("2026-10-26T07:00:00Z"), finishedAt: outcome == nil ? nil : at("2026-10-26T07:01:00Z"), outcome: outcome,
            detail: detail)
    }

    @Test(arguments: [
        (SyncTrigger.launch, "you opened Vesel"), (.foreground, "you opened Vesel"), (.bandEvent, "your Loop asked"),
        (.backgroundRefresh, "iOS woke Vesel"), (.shortcut, "Shortcut"), (.manual, "Sync now"), (.imUp, "I'm up"), (.paired, "after pairing"),
    ])
    func everyTriggerHasItsWords(trigger: SyncTrigger, words: String) {
        #expect(SyncRunWords.trigger(trigger) == words)
    }

    @Test(arguments: [
        (SyncOutcome.success, String?.none, "done"),
        (.partial, nil, "partly done"),
        (.unreachable, "Band not nearby", "Loop not nearby"),
        (.unreachable, "Band didn't start the sync", "Loop didn't answer"),
        (.unreachable, "something else", "Loop not nearby"),
        (.unreachable, nil, "Loop not nearby"),
        (.failed, "Stopped before it finished", "stopped early"),
        (.failed, "No band paired", "no Loop paired"),
        (.failed, "Couldn't read heartRate for 2026-10-26", "didn't finish"),
        (.failed, nil, "didn't finish"),
    ])
    func everyOutcomeHasItsWords(outcome: SyncOutcome, detail: String?, words: String) {
        #expect(SyncRunWords.outcome(run(outcome, detail)) == words)
    }

    @Test func aRunWithoutAnOutcomeIsReadingOnlyWhileTheAppReads() {
        #expect(SyncRunWords.outcome(run(nil), isRunning: true) == "reading now…")
        #expect(SyncRunWords.outcome(run(nil)) == "didn't finish")
    }

    @Test func theStoredWordsAreWhatOlderVersionsStored() {
        #expect(SyncTrigger.imUp.rawValue == "imUp")
        #expect(SyncDetail.notPaired == "No band paired")
        #expect(SyncDetail.notNearby == "Band not nearby")
        #expect(SyncDetail.didNotStart == "Band didn't start the sync")
        #expect(SyncDetail.stoppedEarly == "Stopped before it finished")
    }
}
