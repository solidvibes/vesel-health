---
status: implemented
---

# Calmer morning: "I'm up" waits for the Loop, "Evaluating your night", report on by default, sleep as bars
**Date**: 2026-10-30
**Status**: Implemented 2026-11-01 (phases 1 and 1b built 2026-10-31, phases 2 and 3 on 2026-11-01; owner checks on the iPhone still open)
**Touches**: `docs/decisions/2026-10-30-calmer-morning.md`, `docs/how-it-works/days.md`, `docs/how-it-works/sleep.md`, `docs/how-it-works/band-sync.md`, `docs/how-it-works/alerts.md`, `docs/design/screens.md`, `.agents/skills/data/SKILL.md`, `.agents/skills/layers/SKILL.md`, `.agents/skills/testing/SKILL.md`

## TL;DR
- Three phases, one PR each, in order: 1 morning logic, 2 morning report, 3 sleep bars.
- Phase 1: Today's morning card is one VeselCore decision, `TodayState.morningCard` (none · goodMorning · evaluating), tested.
- Phase 1: last night stored ends the morning: no "I'm up", no Evaluating, whatever the Loop says.
- Phase 1: "I'm up" stores an `ImUpRequest` in `SyncStatusStore` (injected `UserDefaults`), kept across launches, dropped after 6 hours.
- Phase 1: every read first delivers a waiting tap: ask the Loop, end sleep unless already stopped; stamps "night ended".
- Phase 1: Loop not nearby keeps the tap and skips the 5-minute gap; a Loop that refuses drops it (I'm up returns).
- Phase 1: a read that can't reach the Loop keeps the last known sleep status (no more I'm up vanishing).
- Phase 1: "Processing" → "Evaluating your night" card with a small animated line (Theme); "Processing…" → "Evaluating…".
- Phase 1: "Still in bed" while the Loop records → no card. Report off → "It shows here when it's ready."
- Phase 1: pipeline tests with the fake band for every end-sleep path (risk area).
- Phase 2: morning sleep report on by default; migration v6 deletes a stored `alerts.morningReport` once.
- Phase 2: tapping the morning report opens that night's Sleep page on D; others still open Today.
- Phase 3: Sleep joins the bar kinds on Body and the Sleep page's W, M, 3M: blue bars from 0, normal behind.
- Risk areas: phone → band command (end sleep), a database migration (one setting row). Nothing leaves the phone.

## Context
30 October, the owner's morning. The Loop ended the night by itself; Today correctly said "Processing last night". Later "I'm up" came back although last night was in. Cause: `TodayState.showsGoodMorning = bandStillRecordingSleep && !dismissed` never checks whether last night is stored, and `SyncStatusStore.set(sleep:)` sets `bandStillRecordingSleep = status != .stopped`, so a read where the band answered "can't say" (`SleepRecordingStatus.unknown`: Polar's own unknown, or `BandSync.readSleepStatus` after a thrown status call) counted as asleep. Tapping "I'm up" then finished at once because the night was already in.

Separately: "I'm up" needs the Loop in reach (`ContinuedRead.endNight` throws → "Couldn't reach your Loop. Try again."); a read that can't reach the Loop after a relaunch sets `set(sleep: nil)` → `bandStillRecordingSleep = false`, hiding "I'm up" before it can be tapped; the morning sleep report is opt-in and opens Today; sleep on Body and the Sleep page's W/M/3M is a line.

The owner approved the scope card on 2026-10-30 (see the decision file). This plan works out how.

## Constraints
- Rules: `.agents/skills/data/SKILL.md`, `.agents/skills/layers/SKILL.md`, `.agents/skills/testing/SKILL.md`; always-on `AGENTS.md`.
- Packs: none (`docs/stack.md` has no `## Packs`).
- Layers: decisions are pure VeselCore (`TodayState`, `ImUpRequest`, `AlertIdentifier`); band calls only through `BandSync`, one at a time; screens reach the band only through `SyncPipeline`/`ContinuedRead`. `ios/Vesel/Theme/` views take plain values only.
- "Never nag": the morning report is one summary per night the owner asked to be on; quiet hours (22:00–07:00) and "once per night" stay. It softens "quiet by default" of `2026-10-26-background-alerts.md` for this one kind (named in the decision).
- Notification text from `Alert` only; never logged. The tap request holds a time and a flag, no health values, in `UserDefaults` like `sleepEndedAt` and `goodMorningDismissedOn`.
- Time from the injected clock (`VeselClock`), never `Date()` in logic.
- **Risk — changing state on the band:** phase 1 can send `endSleepRecording` from any read while a tap waits. Guarded: only while the tap is under 6 hours old, last night isn't stored, and the band doesn't already say stopped. Never from a read with no tap. Covered by pipeline tests.
- **Risk — database migration:** phase 2 adds `v6`, deleting one `setting` row (`alerts.morningReport`). Never edit `v1`–`v5`.

## Approach

### Phase 1 — morning logic, queued "I'm up", "Evaluating your night"

**VeselCore.** New `ImUpRequest` (`Analysis/ImUpRequest.swift`): `tappedAt: Date`, `missedLoop: Bool`, `Codable`; `static let keptFor: TimeInterval = 6 * 3600`; `isWaiting(at now: Date) -> Bool` = `(0..<keptFor).contains(now.timeIntervalSince(tappedAt))` (a tap time in the future, clock gone back, isn't waiting).

`TodayState`: replace `showsGoodMorning: Bool` with `morningCard: MorningCard`:
```swift
public enum MorningCard: Sendable, Equatable { case none, goodMorning, evaluating(waitingForLoop: Bool) }
```
New inputs `imUp: ImUpRequest?`, `now: Date`. With `stored = latestNight == today` and `waiting = !stored && imUp?.isWaiting(at: now) == true`:
- `lastNightPending = lastNightMissing && (waiting || bandStillRecordingSleep || bandFinishingNight || sync.isReading)` (adds `waiting`).
- `morningCard`, first match: `stored` → `.none`; `waiting` → `.evaluating(waitingForLoop: imUp.missedLoop)`; `bandStillRecordingSleep` → `dismissedGoodMorning ? .none : .goodMorning` (after "Still in bed" the night isn't over: no card); `lastNightPending` → `.evaluating(waitingForLoop: false)`; else `.none`.
- With no night at all (`latestNight == nil`) a waiting tap still shows Evaluating; "I'm up" shows as before.

This is the "can't say" fix: `stored` wins over every band answer, in one place.

**SyncStatusStore** (app). `init(defaults: UserDefaults = .standard)`; `sleepEndedAt` and the request read and write through it (tests pass a throwaway suite, so nothing leaks between test runs and Simulator runs).
- `private(set) var imUp: ImUpRequest?`, JSON under `imUpRequest`. `tapImUp(at:)` stores a new one (`missedLoop: false`); `imUpMissedLoop()` sets the flag; `clearImUp()` removes it.
- `set(sleep:at:)`: nil (Loop not nearby, or nothing read since launch) keeps the last known value instead of clearing it. `.stopped` after recording stamps `sleepEndedAt` as now.
- New `nightEnded(at:)`: always stamps `sleepEndedAt` (and persists it) and sets `bandStillRecordingSleep = false`. Used whenever Vesel itself ended the night, so the 2-hour "Polar is finishing" window starts at delivery even when the in-memory status was nil or false (after a relaunch or an unreachable read).
- `nightOnItsWay(at:)` adds `imUp?.isWaiting(at: now) == true` (its callers already check today and no night).

**SyncPipeline.** New `hasNight(_ day:)` on `AppDatabase` (VeselStorage `Queries.swift`: a row in `sleep_night` or `nightly_recharge` for that night, the union `shownNight` uses). `endSleep()` stays (used by `endNight(_:)` for the Shortcut and now by delivery) and calls `status.nightEnded(at:)` instead of `set(sleep: .stopped)`. In `syncIfDue`, before the `SyncGap` check:
1. `stored = hasNight(clock.today)`; if stored, or the request is past 6 hours, `status.clearImUp()`.
2. `ending = status.imUp?.isWaiting(at: now) == true` (after step 1).
3. `onlyIfDue && !ending` → the `SyncGap` check as now. A waiting tap only exists untried or after "not nearby", so skipping the gap only ever means "try the Loop again", never back-to-back full downloads from a Loop that answers.
4. After `status.set(.reading(...))`, if `ending`, `deliverImUp()`: `bandSync.readSleepStatus()`;
   - nil (not nearby) → `status.imUpMissedLoop()`; keep.
   - `.stopped` → `status.set(sleep: .stopped, at: now)`, clear (the Loop ended it itself; just read).
   - otherwise (`.recording`, `.unknown`) → `try await endSleep()` then clear; a throw (the Loop was near and refused) → clear. "I'm up" comes back by itself (the band still records) so the owner can tap again; no error text.
   Then the read runs as now and fetches the night.
- `endNight(_:)`'s wait-out-a-running-read part moves into `readAfresh(_ trigger:)`, which the I'm up fallback also uses.
- `shortcut()`: skip `endNight` when `sleep == .unknown && hasNight(today)` (rule 3 for the Shortcut too).

**ContinuedRead.** `endNight()` → `imUp()`: `read { runHeld(.imUp, progress:) } otherwise: { pipeline.readAfresh(.imUp) }`; no longer throws. `runHeld` already waits out a running read and reads afresh, so a read that started before the tap never swallows it.

**TodayModel.** `imUp()`: `environment.status.tapImUp(at: clock.now)`, then `await environment.continuedRead.imUp()`. `endingNight` and `endNightFailed` go. `state(readingCard:)` passes `imUp: environment.status.imUp, now: environment.clock.now`.

**Morning report on or off on Today.** `TodaySnapshot` gains `morningReportOn: Bool`, read in `todaySnapshot` from `alertSettings(db)`, so the observation follows the switch.

**Today screen.**
- `GoodMorningCard` loses `working`/`failed`: no "Reading last night…", no "Couldn't reach your Loop. Try again."; the tap hides it at once (the request makes the card Evaluating).
- `ProcessingNightCard` → `EvaluatingNightCard(waitingForLoop:reportOn:)`: title "Evaluating your night"; body, first match: waiting → "Nothing for you to do. Your Loop gets the message as soon as it's near your phone."; report on → "Nothing for you to do. We'll let you know when it's ready."; report off → "Nothing for you to do. It shows here when it's ready." One VoiceOver element: title and body.
- Under the text a thin indeterminate line: new `IndeterminateLine(color:)` in `ios/Vesel/Theme/` (a SwiftUI `ProgressView` in linear style doesn't animate without a value on iOS). A 3 pt capsule track at low opacity with a short capsule sliding across, repeating; Reduce Motion: the still track only; `accessibilityHidden`. Tinted `Theme.Palette.sleep`.
- `TodayView` switches on `state.morningCard`, inside `TimelineView(.periodic(from: .now, by: 30))` like the `LineRows` one below, so the 6-hour and 2-hour windows end on screen without another trigger. The `.noSleep` branch hides its empty state when `morningCard != .none` (was `showsGoodMorning`).

**"Processing" → "Evaluating".** `LineRows.noNight` "Evaluating…"; `JournalModel` sleep and recovery values "Evaluating…"; `SleepPage` header "Evaluating…" and its empty state title "Evaluating your night" (message unchanged); `RecoveryPage` value "Evaluating…"; `RecoveryView` empty state title "Evaluating your night" (message unchanged).

Alternatives ruled out: sending end-sleep inside `BandSync.sync` (changes the fetch order the data rules fix, for no gain: the pipeline already queues band calls one at a time, as the Shortcut does); a retry button on I'm up (owner's rule 1); keeping a refused tap for 6 hours (every check-in would skip the gap and re-download heart rate back to back, and the card would wrongly say the Loop isn't near).

### Phase 1b — the owner's morning of 31 October (built together with phase 1, same PR)

Phone log, 31 Oct: the Loop was out of reach 23:33–08:31; reads at 01:31, 04:08, 07:10, 07:40, 08:11, 08:30, 08:31:09 and 08:31:38 each gave up after exactly 10 s; 08:31:51 read fine. 08:48–09:18 again only "not nearby". Rows 219–222, 224, 228, 236 and 246 never got an ending. "I'm up" didn't show until a read reached the Loop; the "Reading your Loop" card sat in the Dynamic Island with nothing happening.

1. **"I'm up" shows from 03:00 without the Loop.** `TodayState.morningCard`: `.goodMorning` also when `!stored`, no waiting tap, not dismissed, the band isn't known to have stopped the night (`sleepEndedAt` not today) and the clock is in the morning window 03:00–12:00 (`MorningWindow` in VeselCore, from the injected clock and zone). Band recording outside the window still shows it as in phase 1. The tap is kept (phase 1's `ImUpRequest`) and sent when the Loop is reached.
2. **A read waits for the Loop instead of giving up after 10 s.** `WearableSource.reachable(within:)`; the wait depends on the trigger: Sync now, I'm up and opening the app wait up to 60 s, background triggers 20 s (iOS gives ~30 s). While waiting, `SyncStatus` gets a new `.waitingForLoop` and Today shows the calm card "Waiting for your Loop · Reads as soon as it's near your phone." (no error, no Try again); "Can't reach your Loop" with Try again only after the wait ran out on a tap (Sync now / Try again). The band connecting (`BandEvent.connected`) reads even within 5 minutes of a try that never reached the Loop: `SyncGap` counts only tries that reached it (`unreachable` rows don't hold back the next automatic read).
3. **A read never hangs.** A read stops when the Loop drops during it (`drops` changed, or `connectionState` leaves `.connected` for more than 15 s) and when a single band call takes longer than 90 s (heart rate and beat-to-beat backlog included: tested on the fake band with a slow fetch). The stopped read ends as "didn't finish" like a cut-off read: nothing cleared.
4. **The Dynamic Island card only while reading.** `ContinuedRead` first waits for the Loop (as in 2) without iOS's card; only when the Loop is reached does it submit the continued-processing request. On every ending (done, failed, not reached, cancelled, stopped) the task is completed. On launch, no stale card stays: any earlier task identifier still registered is completed.
5. **Why the Loop is away: a connection log.** Migration `v5` adds `band_link (id, at INTEGER, event TEXT, reason TEXT)`: connecting, connected, disconnected (with the SDK's reason), Bluetooth off/on. Times and words only, no health values; rows older than 14 days are deleted at each write. Shown nowhere yet (debug: the Band data report gets a "Connection" list of the last 2 days). Phase 2's migration becomes `v6`.

Tests: `TodayStateTests` (03:00 window, before 03:00 none, after 12:00 none, stopped today → none); `SyncGapTests` (unreachable tries don't hold back the next); `SyncPipelineTests` with the fake band (`.unreachable` then reachable after N s within the wait → reads; a fetch slower than the limit stops the read as cut off, nothing cleared; a drop mid-read stops it); migration test for v5.

### Phase 2 — morning report on by default, tap opens the Sleep page

- `AlertKind.isOnByDefault`: `isWarning || self == .morningReport` (stand-up reminders stay off). `MorningReport`'s "opt-in" comment goes.
- **The owner's stored value.** A switch only has a stored row once it was touched. Never touched → the new default turns it on by itself. Touched (stored "off" or "on") → migration `v6` deletes the `alerts.morningReport` row once, so it follows the new default: on. After that the switch works as always. Chosen over asking him to flip it: he asked for it on, and it is one row.
- `AlertIdentifier` (VeselCore, `Analysis/Alerts.swift`): `make(kind, day) -> "alert.<kind>.<day>"` and `parse(_:) -> (AlertKind, DayKey)?`. `AlertNotifier` uses `make` (same strings as now, so notifications already scheduled still parse); stand-up keeps `alert.standUp` (parses to nil → Today).
- `AppDelegate.didReceive`: `environment.openNotification(response.notification.request.identifier)`. `AppEnvironment.openNotification(_:)`: `.morningReport` → `open(.today, page: PageRoute(kind: .sleep, day: day))` (the notification's night, on D); anything else → `open(.today)`. `openToday()` goes.
- Permission: already asked on the first open after the alerts build; nothing new.

### Phase 3 — sleep as bars

- `TrendKind.isBars`: add `.sleep`. Points span the whole day, the chart draws `RectangleMark` normal + `BarMark` in `Theme.Palette.sleep`, y from 0 (`yDomain` bars branch), scrub rule at the bar's middle.
- `bandColor` stays `color` for sleep (normal in sleep blue at 0.18 behind full-blue bars; steps keep the accent because their bars are muted).
- New `TrendKind.isPerDay` (`.calm`, `.steps`) for wording: `periodSummary` says "Average a day" only for those, so sleep keeps "Average a night". "Hollow dots fall outside it." stays left out for bars (`OverTimePart`, `NightlyDayPart`), now for sleep too.
- `isPartial` stays steps-only. Same chart, same page: no new chart.

## Files

### Phase 1
- `ios/Packages/VeselCore/Sources/VeselCore/Analysis/ImUpRequest.swift` — new: the kept tap and its 6-hour life.
- `ios/Packages/VeselCore/Sources/VeselCore/Analysis/TodayState.swift` — `MorningCard`, `imUp`/`now` inputs, stored night ends the morning.
- `ios/Packages/VeselCore/Tests/VeselCoreTests/TodayStateTests.swift` — morning cases (step 1).
- `ios/Packages/VeselStorage/Sources/VeselStorage/Queries.swift` — `hasNight(_:)`.
- `ios/Packages/VeselStorage/Sources/VeselStorage/Observations.swift` — `TodaySnapshot.morningReportOn`.
- `ios/Vesel/Background/SyncStatusStore.swift` — injected defaults; the request; nil keeps last status; `nightEnded(at:)`.
- `ios/Vesel/Background/SyncPipeline.swift` — deliver a waiting tap before each read; `readAfresh`; Shortcut guard.
- `ios/Vesel/Background/ContinuedRead.swift` — `endNight()` → `imUp()`, no throw.
- `ios/Vesel/Today/TodayModel.swift` — tap stores the request, then reads; failure state gone.
- `ios/Vesel/Today/GoodMorningCard.swift` — I'm up card without working/failed; `EvaluatingNightCard`.
- `ios/Vesel/Theme/IndeterminateLine.swift` — new: the moving line, still under Reduce Motion.
- `ios/Vesel/Today/TodayView.swift` — switch on `morningCard` inside a 30-second `TimelineView`.
- `ios/Vesel/Today/LineRows.swift`, `ios/Vesel/Journal/JournalModel.swift`, `ios/Vesel/Pages/SleepPage.swift`, `ios/Vesel/Pages/RecoveryPage.swift`, `ios/Vesel/Recovery/RecoveryView.swift` — "Evaluating…" / "Evaluating your night".
- `ios/VeselWidgetsTests/SyncPipelineTests.swift` — end-sleep paths (step 2); `SyncStatusStore(defaults:)` with a throwaway suite in every test here.
- Docs: `docs/how-it-works/days.md`, `sleep.md`, `band-sync.md`, `docs/design/screens.md` (Planned → Built), `CHANGELOG.md`.

### Phase 2
- `ios/Packages/VeselCore/Sources/VeselCore/Analysis/Alerts.swift` — default on; `AlertIdentifier`.
- `ios/Packages/VeselCore/Sources/VeselCore/Analysis/MorningReport.swift` — comment no longer says opt-in.
- `ios/Packages/VeselCore/Tests/VeselCoreTests/AlertsTests.swift` — default and identifier round trip.
- `ios/Packages/VeselCore/Tests/VeselCoreTests/MorningReportTests.swift` — `offUntilTheOwnerTurnsItOn` becomes "on until the owner turns it off" (settings with it off → nil; empty settings → due).
- `ios/Packages/VeselStorage/Sources/VeselStorage/Migrations.swift` — `v6`.
- `ios/Packages/VeselStorage/Tests/VeselStorageTests/MigrationTests.swift` — `migratingTwiceChangesNothing` expects v1…v6; new test: stored "off" before v6 reads on after, other switches untouched.
- `ios/Vesel/Background/AlertNotifier.swift` — ids from `AlertIdentifier`.
- `ios/Vesel/AppDelegate.swift` — pass the notification id.
- `ios/Vesel/AppEnvironment.swift` — `openNotification(_:)` replaces `openToday()`.
- Docs: `docs/how-it-works/alerts.md`, `docs/design/screens.md`, `CHANGELOG.md`.

### Phase 3
- `ios/Vesel/Body/BodyModel.swift` — sleep in `isBars`; `isPerDay` for "a day" wording.
- `ios/Vesel/Pages/OverTimePart.swift`, `ios/Vesel/Pages/NightlyDayPart.swift` — check the bars caption reads right for sleep (no change expected).
- Docs: `docs/how-it-works/sleep.md`, `docs/design/screens.md`, `CHANGELOG.md`.

## Steps

### Phase 1
1. `ImUpRequest` + `TodayState.morningCard`. Tests: stored night → `.none` with the band recording (also "can't say", passed as recording), finishing, reading or a waiting tap; recording, no tap → `.goodMorning`; recording + dismissed → `.none`; tap waiting → `.evaluating(missedLoop)`; tap 6 h old → back to band state; a tap time in the future isn't waiting; `lastNightPending` true with a waiting tap and band stopped long ago; no night at all + waiting tap → Evaluating. Fast checks green.
2. `hasNight`, `SyncStatusStore`, `SyncPipeline`, `ContinuedRead.imUp`, `TodayModel`. `SyncPipelineTests` (fake band, in-memory database, `FixedClock`, throwaway defaults; `band.calls` counts `endSleepRecording`):
   - tap waiting, `stillAsleep` → one `endSleepRecording`, request cleared, `sleepEndedAt` stamped, night fetched;
   - no tap, `stillAsleep` → no `endSleepRecording`;
   - tap waiting, night already stored → none, request cleared;
   - tap waiting, band says stopped (`normal`) → none, request cleared;
   - tap waiting, `.unreachable` → none, request kept with `missedLoop`, `bandStillRecordingSleep` kept;
   - tap 6 h old → none, cleared;
   - `run(.bandCheckIn, onlyIfDue: true)` within 5 minutes of a read: reads with a waiting tap, skipped without;
   - Shortcut: band "can't say" (`setSleepStatus(.unknown)`) + night stored → no `endSleepRecording`.
   The refused-by-a-near-Loop branch has no fake failure; it is three lines (clear) and is left to review.
3. Cards, `IndeterminateLine`, the `TimelineView`, the "Evaluating" wording on Today, Journal, Sleep and Recovery pages.
4. Simulator flows (Verification), screenshots of each Today state.
5. Docs Built, `CHANGELOG.md` one line.

### Phase 2
1. [x] Default on, `AlertIdentifier`, comment, tests (AlertsTests, MorningReportTests).
2. [x] Migration `v6` + migration tests.
3. [x] `AlertNotifier`, `AppDelegate`, `AppRouter.openNotification` (see Deviations); `AppRouterTests` for the id → route mapping. The morning report tap itself is owner-only on the iPhone.
4. [x] Docs Built, changelog.

### Phase 3
1. [x] `isBars`/`isPerDay` done; the Simulator screenshots of Body's Sleep card and the Sleep page W, M, 3M are left unchecked: the owner checks on the iPhone.
2. [x] Docs Built, changelog.

## Decisions
1. "I'm up" with the Loop out of reach: tap kept across launches, sent at the next read that reaches the Loop; if the Loop already ended the night, just read. Minutes between tap and delivery may count as in bed. — **mine**
2. One "Evaluating your night" card from the tap (or the Loop ending the night) until last night is stored; the bodies above; "Evaluating…" everywhere "Processing…" was; a thin indeterminate line; no "Couldn't reach your Loop" on I'm up. — **mine**
3. Once last night is stored the morning is over; "can't say" counts as asleep only until then. Applied to the Shortcut too. — **agent's**
4. Morning sleep report on by default; its tap opens that night's Sleep page on D; others open Today. — **mine**
5. The owner's stored morning-report value is reset once by migration `v6` so it is on. — **agent's**, flagged (one-time, reversible with the switch).
6. Sleep as blue bars from 0 with the normal shaded behind, Body and Sleep W/M/3M. — **mine**
7. After 2 hours with nothing: "Last night isn't in yet. It fills in on the next read." unchanged; the 2 hours start when the Loop got the tap. — **agent's**
8. A tap the Loop never gets is dropped after 6 hours, so it can't end the next night's sleep. — **agent's**, flagged.
9. The tap is delivered by the pipeline before each read (ask, then end), not inside `BandSync.sync`. — **agent's**
10. After "Still in bed" while the Loop still records: no card (the night isn't over). Recovery and Sleep still say "Evaluating…". — **agent's** (main thread)
11. "Waiting for the Loop" wording only after a read tried and didn't find the Loop; right after the tap the plain body shows. — **agent's**
12. Sleep's shaded normal stays sleep blue (lighter), not the accent steps use. — **agent's**
13. Morning report off: the Evaluating body reads "Nothing for you to do. It shows here when it's ready." — **agent's** (main thread)
14. A read that can't reach the Loop keeps the last known sleep status, so "I'm up" stays until the Loop is read. — **agent's**
15. A Loop that is near but refuses the end command drops the tap; "I'm up" comes back to tap again, no error text. — **agent's**

16. (31 Oct) "I'm up" shows 03:00–12:00 until last night is stored, without waiting for the Loop. — **mine**
17. (31 Oct) Reads wait up to 60 s (tap or opening) / 20 s (background) for the Loop; a calm "Waiting for your Loop" card, no error loop. — **mine**
18. (31 Oct) Dynamic Island card only once the Loop is reached; reads stop on a drop or a 90 s stuck band call. — **mine**
19. (31 Oct) A connection log (`band_link`, migration v5, 14 days, no health values) to find out why the Loop is away. — **mine**

## Verification
Checks: the contract's fast checks, then full (the app's `xcodebuild test` runs `SyncPipelineTests`).

- VeselCore: `TodayState` morning tests, `AlertIdentifier` round trip, default-on and morning-report tests.
- VeselStorage: migration tests for `v5` (connection log) and `v6` (morning report).
- App (Simulator tests): the `SyncPipelineTests` end-sleep cases.
- Simulator (run per the contract):
  - `-VeselScenario stillAsleep`: "Good morning — I'm up"; tap → the card goes, "Evaluating your night" with "We'll let you know when it's ready." and the moving line, Recovery and Sleep "Evaluating…"; when the read stores the night the card goes and the numbers show.
  - "Still in bed" on `stillAsleep`: no card.
  - Waiting for the Loop: launch `stillAsleep` once (stores "recording"), relaunch with `-VeselScenario stillAsleep -VeselFakeFailure unreachable`: "I'm up" still shows; tap → "Your Loop gets the message as soon as it's near your phone."; relaunch with `-VeselScenario stillAsleep` and no failure → the Syncing page shows a read, the night is ended (the fake band now says stopped) and read, the card goes.
  - `-VeselScenario normal` (last night in): no I'm up, no Evaluating card.
  - Morning report switched off in Loop & settings, then the `stillAsleep` tap: "It shows here when it's ready."
  - `-VeselPage sleep -VeselPeriod w|m|3m` and Body: blue bars from 0, shaded normal, "Average a night".
  - Morning report tap: not drivable headless; **owner-only** on the iPhone.
- **Owner-only (iPhone + real Loop):** tap I'm up with the Loop in another room, bring it back, the night ends and arrives; the morning report arrives without touching the switch and opens last night's Sleep page; a morning where the Loop ends the night itself never brings "I'm up" back after the night is in.

## Rule gaps
Resolved in Phase 5: none applied yet; each describes the end state and lands with its phase.
- (Phase 1) `layers`: "Whether Today shows I'm up or Evaluating comes from `TodayState.morningCard` (VeselCore); a stored last night ends the morning whatever the band says."
- (Phase 1) `data`: "A waiting 'I'm up' (`ImUpRequest`) is delivered by `SyncPipeline` before a read, only while under 6 hours old and last night isn't stored; no ordinary read ends sleep without one. Ending the night from Vesel stamps `nightEnded(at:)`."
- (Phase 1) `testing`: "App tests build `SyncStatusStore(defaults:)` on a throwaway suite, never `.standard`."
- (Phase 2, applied) `data`: "A notification's id is `AlertIdentifier` (VeselCore); its tap goes where the id says."

## Deviations
- (Phase 2) `openNotification(_:)` lives on `AppRouter`, not `AppEnvironment`: routing moved there in `docs/plans/2026-10-31-exemplar-polish.md` C1. `AppDelegate` calls `startup.environment?.router.openNotification(_:)`; with no database a tap does nothing, as before. Tested in `AppRouterTests`.
- (Phase 2) The v5 migration test now migrates only up to v5 and reads the rows directly (`AppDatabase(_:)` migrates to the latest), since v6 deletes the morning report row it checks.
