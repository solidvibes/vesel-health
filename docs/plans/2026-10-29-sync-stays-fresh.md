---
status: implemented
---

# Sync stays fresh
**Date**: 2026-10-29
**Status**: Implemented 2026-10-29 (owner checks on the iPhone still open)
**Touches**: `docs/how-it-works/band-sync.md`, `docs/how-it-works/alerts.md`, `.agents/skills/data/SKILL.md`, `CHANGELOG.md`

Decision: `docs/decisions/2026-10-29-stand-up-reminders.md` (phase 3).

## TL;DR
- Problem: a read stores nothing until every kind is fetched; background reads (~30 s) get cut off, so most store nothing.
- Phase 1: readings with data show up as each kind arrives. What clearing relies on (the ledger's empty days, and every heart-rate and beat-to-beat day) is written only after a whole read with no Bluetooth drop.
- Phase 1 order: sleep + Nightly Recharge (night over), daily summary, activity samples, skin temperature, heart rate, PPI.
- Phase 1 `ClearPlan`: the second empty read of a day must be at least an hour after the one before it.
- Phase 1 gap: app-open waits 5 min after the last *finished* read; automatic triggers keep 5 min after the last *started* one (`SyncGap`, VeselCore, tested).
- Phase 1 docs: drop the false "every 5 minutes" claim.
- Phase 2: the Loop's inactivity, exercise and battery/charging notices wake a read ("your Loop checked in"); a long read while the phone charges.
- Phase 3: "Stand-up reminders" switch in Loop & settings → Alerts, off by default; the Loop's own inactivity alert becomes a silent notification.
- Phase 4: Sync now and I'm up keep reading after you leave Vesel, with iOS's progress card and a cancel.
- Clearing the band: still only after a whole read, never today/yesterday, a cut-off read clears nothing.
- No migration, nothing leaves the phone. Honest limit: nothing on the Loop reads on a schedule.

## Context
At 19:00 the newest steps and heart rate were from 10:00; opening, closing and reopening Vesel showed nothing new. Polar Flow did the same; a Garmin never does.

Found in the code:
1. `BandSync.fetchStoreAndClear` fetches every kind, each from the day before its last stored day through today, holds it all in `byDay`, and saves only after the last fetch. Then it clears.
2. Background reads get ~30 s (`BackgroundTime` = `beginBackgroundTask`; `BGAppRefreshTask`). On expiry `SyncPipeline.expire()` cancels the sync and suspends the database: nothing is stored. The next read starts over.
3. Triggers: band reconnect (gap 5 min), `sleepEnded`, `syncRequired`, background app refresh (rare), app opened, Sync now, Shortcut, I'm up. During the day the Loop stays connected, so nothing reads on a schedule. There is **no** timer while the app is on screen: `band-sync.md`'s "every 5 minutes" was wrong.
4. `SyncPipeline.syncIfDue` skips an app-open read when the last read *started* under 5 minutes ago and the night is over, even if that read was cut off. Part of the symptom: open → close (cut off) → reopen → skipped.

Polar BLE SDK 8.5.0 (`ios/build/SourcePackages/checkouts/polar-ble-sdk`):
- `PolarAutomaticSamplesUtils.read247HrSamples` / `read247PPiSamples` list **every** autosample file (`AUTOS\d{3}.BPB`) on the band, download each, group by the day inside, and **catch and skip** any file that fails. `getNightlyRecharge` and the per-day reads return nothing for a failed date. A Bluetooth drop mid-kind can come back as "no data" or as part of a day, without an error; with `automaticReconnection` the Loop may be back seconds later. Heart rate and PPI come from the same files; their cost grows with what is on the band, not with the date range. Whether a day can span two files is unknown.
- `documentation/SyncImplementationGuideline.md`: the SDK doesn't support Polar's auto-sync; it recommends resumable stages and "more often with smaller amounts".
- `documentation/Device Error Codes & D2H Notifications.md`, Polar 360 firmware (Loop shares it) sends `inactivityAlert` (4), `syncRequired` (7), `restApiEvent` (18), `exerciseStatus` (19). None is periodic. `restApiEvent` is the sleep-state notice `observeSleepRecordingStatus` already turns into `.sleepEnded`.
- Battery Service notifications are on after every connect; `batteryLevelReceived` / `batteryChargingStatusReceived` fire per notification and once per connect with the cached value. Whether the Loop sends them between connects is not documented.
- Inactivity notice: `PbPFtpInactivityAlert.countdown` (minutes; `0` = fired, `>0` = pre-alert), readable from the public raw `PolarD2HNotificationData.parameters`. The band's own setting has no public read or write; `setPolarUserDeviceSettings` rebuilds the general settings from location only, so Vesel must never call it.
- iOS: installed SDK is iPhoneOS 27.1; `BGContinuedProcessingTask` API available from iOS 26.0 (the deployment target). `BGContinuedProcessingTaskRequest(identifier:title:subtitle:)`, `strategy` (`.queue` default, `.fail`); the task conforms to `NSProgressReporting` (no progress → iOS may end it as stalled) and has `updateTitle(_:subtitle:)`. Permitted identifier in wildcard form `<bundle id>.<context>.*`, submitted as `<bundle id>.<context>.<suffix>`; its registration is exempt from the before-launch-ends rule; submitted by the app in the foreground. The header doesn't say whether a handler may be registered under the wildcard string, and registering one identifier twice is an error.

## Constraints
- Rules: `AGENTS.md`, `.agents/skills/data/SKILL.md`, `.agents/skills/layers/SKILL.md`, `.agents/skills/testing/SKILL.md`.
- Packs: none (`docs/stack.md` has no `## Packs`).
- **Risk area: deleting data from the band.** Clearing reads only the ledger (`band_ledger`). Invariants, each tested:
  - A read is **whole** when every fetch returned, the task wasn't cancelled, and the Loop's drop count is the same as when the read started. Only a whole read writes empty days to the ledger, writes heart-rate and PPI ledger rows, and clears.
  - Mid-read, only per-day kinds (sleep, Nightly Recharge, daily summary, activity samples, skin temperature) get ledger rows, and only for days with data: each is one whole record per day from the SDK.
  - Per-day kinds: a data day is saved mid-read only if no day before it in this read is empty-with-no-ledger-row yet, so `lastStoredDay` (`MAX(day)`) never jumps past a day with no row.
  - A band type (e.g. `autoSample` = heart rate + PPI) clears a day only when every kind it covers is stored for that day (unchanged).
  - Never today or yesterday; an empty day settles after two empty reads after it ended, now at least an hour apart.
  - A stored day with data is never replaced by an empty re-fetch (unchanged).
- Every background entry point resumes the database first and suspends it at the end and in its expiration handler (data rule).
- All band calls go through `BandSync`, one at a time. `PolarBandEvents` only turns notices into `BandEvent`s and counts drops. Screens reach the band only through `SyncPipeline`.
- Never nag: the new wakes only read. Exception: phase 3, opt-in, off by default.
- Notification text from `Alert` only (VeselCore); never logged; local only. Nothing leaves the phone; never log health values.

## Approach
**Store as you go, clear only after a whole read (phase 1).**
- `WearableSource` gets `var drops: Int { get async }`: `PolarBandEvents.deviceDisconnected` adds one; the fake band counts its acted-out drops. `BandSync` reads it right after `startSync`.
- Per kind, in the new order: `fetch` → `try Task.checkCancellation()` → then:
  - **Per-day kinds:** sorted by day, data payloads are saved with their ledger rows (`database.save`) until the first empty payload whose day has no ledger row yet; that payload and the rest of the kind go to `held`. An empty re-read of a day that already has a row (e.g. a day not worn, read before) doesn't hold anything back.
  - **Heart rate and PPI:** data payloads' readings are saved now (`database.saveReadings`: typed rows only, no `raw_export`, no ledger row); every payload goes to `held`. So partial days (a drop between files) are visible but never count for clearing.
  - `progress(.fetched(kind))`.
- After the last kind: cancellation check; drop count unchanged, else throw `BandSyncError.lostBand` (logged "didn't finish"); save `held` with `database.save` (readings, raw export, ledger, as today; a whole read re-fetches each heart-rate/PPI day in full, so the stored day is complete); drop count checked again; then clear as today.
- Worked-out numbers: `MetricsUpdater` recomputes the last 3 nights every read and `StressUpdater` the recent days, so readings saved without a ledger row still reach today's and last night's numbers; older days catch up when their ledger row lands.

Per kind, not per day: heart rate and PPI download every autosample file per call; splitting by day would multiply that.

**Order (phase 1).** `[.sleep, .nightlyRecharge]` (night over) + `[.dailySummary, .activitySamples, .skinTemperature, .heartRate, .ppi]`. Heart rate and PPI last: each downloads every autosample file, so a backlog makes both slow, and only reads with time (app open, long read, continued read) finish them and clear `autoSample`.

**Empty reads an hour apart (phase 1).** `ClearPlan.isStored`: an empty day counts once `earlierEmptyAt >= dayEnd` and `storedAt - earlierEmptyAt >= 1 h`. `earlier_empty_at` holds the empty read just before the latest, so a not-worn day read every few minutes settles at the first pair of consecutive empty reads an hour apart (always by the next morning: nights have long gaps). No schema change.

**Gap (phase 1).** Pure `SyncGap.isDue(trigger:now:lastStartedAt:lastFinishedAt:sleepStatus:)` (VeselCore), used by `syncIfDue`:
- `.foreground`: not due only if the last *finished* read (`lastSuccessfulSync()`) ended under 5 minutes ago and the night is over.
- Automatic `onlyIfDue` triggers (reconnect, check-in): not due if the last read *started* under 5 minutes ago (`latestSyncRun()`), as today, so failing reads can't turn a stream of notices into back-to-back downloads.
- A time in the future (clock went back) is not recent.

**More reads (phase 2).**
- `PolarBandEvents`: `inactivityAlert` pre-alerts (see phase 3) and `exerciseStatus` → `BandEvent.checkIn`; battery level and charging changes (`api.deviceInfoObserver = bandEvents`) → `.checkIn`. One `.checkIn` follows every `.connected` (cached battery value). `restApiEvent` is left out (already `.sleepEnded`).
- Event buffering `.unbounded` (tiny events; nothing dropped). `BandWakeHandler` stays serial, so `.connected` (re-subscribe, live heart rate) runs before reads triggered after it, and `.sleepEnded` / `.syncRequested` queued behind a read start a new read after it, as today. `.checkIn` → `run(.bandCheckIn, onlyIfDue: true)`: check-ins queued behind a read end at once on the 5-minute gap.
- Long read: `BGProcessingTaskRequest("app.vesel.ios.catchup")`, `requiresExternalPower = true`, earliest begin one hour out, submitted only when none is pending (`getPendingTaskRequests`).
- **Task-held reads** (long read, phase 4): `SyncPipeline.runHeld(_ trigger:, task:)` waits for any running read to end, then starts a fresh read in `BackgroundTime`'s held mode: database resume/suspend bookkeeping only, no `beginBackgroundTask` (whose ~30 s expiry would cancel it). The task's expiration handler cancels it.
- Fixed times of day: the existing "Sync Vesel" Shortcut in a personal automation. No app change.

**Stand-up reminders (phase 3).** `AlertKind.standUp` ("Stand-up reminders", off by default, not a warning): the switch appears in Loop & settings → Alerts with no view change. `PolarMapping.inactivityCountdown(_ parameters: Data) -> Int?`: field 1 varint, unknown fields skipped, empty → 0, malformed → nil. Countdown 0 → `BandEvent.stillTooLong(at: Date)`; >0 or nil → `.checkIn`. `BandWakeHandler` starts a separate `Task` for `.stillTooLong` (out of the serial queue, never behind a read): older than 5 minutes → dropped; else `AppEnvironment.standUpReminder()` in its own `BackgroundTime` reads `alertSettings()`, and if on and `AlertTiming.delivery` is `.now`, `AlertNotifier.standUp(_:)` posts `StandUp.alert(day:)` under the fixed id `alert.standUp`. No sound, no `alert_event` row, never on Today. The serial queue then treats it as a `.checkIn`.

**Keep reading after you leave (phase 4).** Sync now (Syncing page, Loop & settings, Today's retry) and I'm up (Today):
- From the tap (foreground): register a handler for a fresh `"<bundle id>.read.<UUID>"`, then submit `BGContinuedProcessingTaskRequest(identifier:, title: "Reading your Loop", subtitle: "Keeps going if you leave Vesel")` with `strategy = .fail`.
- Handler: `runHeld(trigger, task:)` (I'm up: end the night first, as `endNight`). Progress: `.loopFound` 1 unit, `.kinds(k)` total `1 + k.count`, each `.fetched` +1, from the fresh read's own listener. Completes with `success: outcome == .success`.
- Expiry or cancel in iOS's card: `bandSync.cancelSync()`; if the app is in the background, `pipeline.expire()`. Like any cut-off read: nothing cleared.
- Fallbacks: submit throws, or the handler hasn't started 5 s after submit → run the read as today; a handler that starts after that completes at once without reading. The caller always awaits an outcome, so the Sync now error card works as before.
- Limit: progress moves per kind. With a backlog, heart rate and PPI can take minutes without a step, and iOS may end the task as stalled (then it is a cut-off read). The SDK gives no per-file progress.
- No new sync-log trigger. `project.yml`: `$(VESEL_BUNDLE_PREFIX).ios.read.*` permitted.

Ruled out:
- A timer while the app is open; keeping Vesel alive with the live heart-rate stream; undocumented REST events; per-day heart-rate/PPI saving (multiplies full-band downloads).

## Files
Phase 1
- `ios/Packages/VeselWearable/Sources/VeselWearable/WearableSource.swift`: `drops`.
- `ios/Packages/VeselWearable/Sources/VeselWearable/Polar/PolarBandEvents.swift`, `Polar/PolarWearableSource.swift`: count drops in `deviceDisconnected`; expose `drops`.
- `ios/Packages/VeselWearable/Sources/VeselWearable/BandSync.swift`: store as you go, `held`, whole-read checks, new order, `BandSyncError.lostBand`.
- `ios/Packages/VeselWearable/Sources/VeselWearable/ClearPlan.swift`: one-hour spacing.
- `ios/Packages/VeselWearable/Sources/VeselWearable/FakeWearableSource.swift`: `drops`; `dropMidway(_ kind:, reconnects: Bool)`: that kind comes back all empty and the drop count goes up; later calls throw, or (reconnects) succeed.
- `ios/Packages/VeselWearable/Tests/VeselWearableTests/BandSyncTests.swift`, `BandSyncStreamTests.swift`, `ClearPlanTests.swift`.
- `ios/Packages/VeselStorage/Sources/VeselStorage/Queries.swift`: `saveReadings(_:)` (typed rows of data payloads only); `save(_:fetchedAt:)` comment ("fetched payloads, any kinds and days, in one transaction").
- `ios/Packages/VeselStorage/Tests/VeselStorageTests/LedgerTests.swift`: `saveReadings` writes rows, no ledger, no raw export; a later `save` of the same day adds them.
- `ios/Packages/VeselStorage/Tests/VeselStorageTests/MetricsUpdaterTests.swift`: a recent night's numbers change when more of its readings arrive later.
- `ios/Packages/VeselCore/Sources/VeselCore/Models/SyncGap.swift`, `ios/Packages/VeselCore/Tests/VeselCoreTests/SyncGapTests.swift`.
- `ios/Vesel/Background/SyncPipeline.swift`: `syncIfDue` uses `SyncGap`; comments. `ios/Vesel/AppEnvironment.swift`: `foreground()` comment.
- `docs/how-it-works/band-sync.md`, `CHANGELOG.md`.

Phase 2
- `WearableSource.swift`: `BandEvent.checkIn`. `PolarBandEvents.swift`: `exerciseStatus` and inactivity → `.checkIn`; `PolarBleApiDeviceInfoObserver` (battery, charging; DIS methods empty); `.unbounded`. `PolarWearableSource.swift`: `api.deviceInfoObserver = bandEvents`.
- `ios/Packages/VeselCore/Sources/VeselCore/Models/SyncRun.swift`, `SyncRunWords.swift`: `bandCheckIn` "your Loop checked in", `longRead` "long read while charging".
- `ios/Vesel/Background/BandWakeHandler.swift`: `.checkIn` → `run(.bandCheckIn, onlyIfDue: true)`.
- `ios/Vesel/Background/SyncPipeline.swift`: `BackgroundTime` held mode; `runHeld(_:task:)`.
- `ios/Vesel/Background/BackgroundScheduler.swift`: processing task register/schedule.
- `ios/project.yml`: `processing` mode, `app.vesel.ios.catchup`; `cd ios && xcodegen generate`.
- `docs/how-it-works/band-sync.md`, `CHANGELOG.md`.

Phase 3
- `ios/Packages/VeselCore/Sources/VeselCore/Analysis/Alerts.swift`: `AlertKind.standUp` (`isOnByDefault`, `isWarning` false). `Analysis/StandUp.swift`: `StandUp.alert(day:)`.
- `WearableSource.swift`: `BandEvent.stillTooLong(at:)`. `Polar/PolarMapping.swift`: `inactivityCountdown`. `PolarBandEvents.swift`: mapping.
- `ios/Packages/VeselWearable/Tests/VeselWearableTests/PolarMappingTests.swift`: empty → 0, `[0x08, 0x00]` → 0, `[0x08, 0x05]` → 5, a multi-byte varint, an unknown field first, truncated → nil.
- `ios/Vesel/Background/BandWakeHandler.swift`, `ios/Vesel/AppEnvironment.swift` (`standUpReminder()`), `ios/Vesel/Background/AlertNotifier.swift` (`standUp(_:)`).
- `docs/how-it-works/alerts.md`, `CHANGELOG.md`.

Phase 4
- `ios/Vesel/Background/ContinuedRead.swift`: register-then-submit, handler, progress, expiry, fallbacks.
- `ios/Vesel/AppEnvironment.swift`: holds `ContinuedRead`.
- `ios/Vesel/Loop/SyncingView.swift`, `ios/Vesel/Loop/LoopSettingsModel.swift`, `ios/Vesel/Today/TodayModel.swift`: Sync now and I'm up through it.
- `ios/project.yml`: `$(VESEL_BUNDLE_PREFIX).ios.read.*`; `xcodegen generate`.
- `docs/how-it-works/band-sync.md`, `CHANGELOG.md`.

## Steps
### Phase 1: keep what each read gets
- [x] 1. Drop count: `WearableSource.drops`, Polar and fake.
- [x] 2. `saveReadings` + storage test.
- [x] 3. `BandSync.fetchStoreAndClear` as in Approach. Doc comment: "Readings show as each kind arrives; empty days, heart-rate and beat-to-beat ledger rows and clearing only after a whole read".
- [x] 4. `ClearPlan.isStored` one-hour spacing.
- [x] 5. Tests (fake band):
   - PPI fails: earlier per-day kinds have data rows, heart rate has readings but no ledger rows, no empty rows, nothing cleared, `.failed`, last call `stopSync`.
   - `dropMidway(.heartRate, reconnects: true)` (later calls succeed, PPI fine): no heart-rate ledger rows, no empty rows of any kind, nothing cleared, outcome `.failed`. Two such reads more than an hour apart: still nothing. A whole read after: stores and clears as usual.
   - `dropMidway(.heartRate, reconnects: false)`: same, nothing cleared.
   - A day not worn, before days with data, never read yet: a failed read doesn't store the later per-day data days; a whole read does; after that, a failed read stores them.
   - After a read where PPI failed, a whole read stores PPI, then clears `autoSample` through the day before yesterday.
   - Cancelled mid-read (`setFetchDelay`, `cancelSync`): earlier data kept, nothing cleared.
   - Order of `.kinds`.
   - ClearPlan: empty reads 10 minutes apart don't settle; reads every 10 minutes then one an hour after the last do. Existing clearing tests pass (clock steps over an hour where needed).
- [x] 6. `SyncGap` + tests; `syncIfDue` uses it.
- [x] 7. `MetricsUpdaterTests` case.
- [x] 8. Comments; `band-sync.md` phase 1 to Built; CHANGELOG ("A read cut short in the background now keeps what it got, so steps and heart rate stay fresh.").

### Phase 2: more chances to read
- [x] 9. `BandEvent.checkIn`, mapping, device-info observer, `.unbounded`, `SyncTrigger.bandCheckIn`, `BandWakeHandler` case.
- [x] 10. `BackgroundTime` held mode, `runHeld`, `SyncTrigger.longRead`, processing task, `project.yml`, `xcodegen generate`.
- [x] 11. `SyncRunWords` cases (no test restating words); `band-sync.md` to Built; CHANGELOG ("Vesel now also reads when your Loop checks in during the day, and catches up with a longer read while the phone charges.").

### Phase 3: stand-up reminders (opt-in)
- [x] 12. `AlertKind.standUp`, `StandUp.alert(day:)`; every `switch` over `AlertKind` compiles.
- [x] 13. `inactivityCountdown` + tests; `BandEvent.stillTooLong(at:)`; mapping.
- [x] 14. `standUpReminder()`, `AlertNotifier.standUp`, out-of-queue handling with the 5-minute age check. Simulator: Loop & settings shows "Stand-up reminders", off. `alerts.md` to Built; CHANGELOG ("Turn on Stand-up reminders in Loop & settings to get your Loop's sit-too-long alert on your iPhone.").

### Phase 4: keep reading after you leave
- [x] 15. `ContinuedRead` as in Approach; wire Sync now and I'm up; `project.yml`; `xcodegen generate`. `band-sync.md` to Built; CHANGELOG ("Sync now and I'm up keep reading after you leave Vesel, with a progress card you can cancel.").

## Decisions
1. **mine** — Save as you go; cheap visible kinds first; a long read when iOS allows; a cut-off read doesn't block the next app-open read.
2. **mine** — Stand-up reminders as opt-in phase 3.
3. **agent's** — A read counts for clearing only if whole: every fetch returned, not cancelled, no Bluetooth drop during it (review 2: A). Hard to undo: no.
4. **agent's** — Heart rate and PPI readings are saved mid-read without ledger rows; their ledger rows come only with a whole read (review 2: C). Partial days can show, never clear. Cost: older heart-rate/PPI days' worked-out numbers catch up only after a whole read (today's and last night's are always recomputed).
5. **agent's** — Per-day kinds hold back data days only behind a day never read before that came back empty (review 2: I, narrowed). Cost in plain words: after a day the Loop wasn't worn, newer sleep and steps wait for one whole read; after that they show as they come.
6. **agent's** — The second empty read must be at least an hour after the one before it; compares the latest two reads (review 2: H).
7. **agent's** — Per kind, not per day; order sleep, Nightly Recharge, daily summary, activity, skin temperature, heart rate, PPI.
8. **agent's** — Gap: app-open from the last finished read, automatic triggers from the last started read, in `SyncGap` (VeselCore, `swift test`) rather than a hosted `SyncPipelineTests`: the testing rule puts logic in packages and `SyncPipeline` needs `UIApplication`.
9. **agent's** — A failed or cut-off read still logs "didn't finish"/"stopped early"; `partial` stays unused (it would hide the Sync now error card).
10. **agent's** — Check-ins: inactivity pre-alerts, exercise, battery, charging; not `restApiEvent`.
11. **agent's** — Band events stay serial (review 2: D); unbounded buffer; check-ins behind a read are ended by the 5-minute gap instead of a separate "one pending" flag (same effect, less code). Only `.stillTooLong` runs outside the queue.
12. **mine** — Stand-up reminders, opt-in, off by default; an exception to "Never nag".
13. **agent's** — Vesel never reads or changes the band's inactivity setting.
14. **agent's** — Only countdown 0 notifies; pre-alerts and unreadable countdowns only wake a read; a reminder older than 5 minutes is dropped. Silent, nothing 22:00–07:00, newest replaces the last, no `alert_event` row, not on Today.
15. **agent's** — Long read and continued read: wait for a running read, then a fresh read on the task's own time, outside `beginBackgroundTask` (review 2: E). Progress comes from the fresh read's listener, so it isn't 0 % from joining.
16. **agent's** — Processing task submitted only when none is pending.
17. **mine** — Phase 4. **agent's**: register a concrete identifier right before each submit (review 2: G); `.fail` plus a 5-second handler timeout fall back to today's read; no new sync-log trigger.
18. **agent's** — Phase 4's progress mapping stays in the app (three lines); verified by owner checks only (review 2: J).
19. **agent's** — New words: "your Loop checked in", "long read while charging"; "Time to move" / "Your Loop says you've been still for a while."; "Reading your Loop" / "Keeps going if you leave Vesel". Owner to confirm.
20. **agent's** — No in-app how-to for the Shortcut automation; no tests that restate words or defaults.

21. **mine** — Reading at fixed times: the owner sets up "Sync Vesel" in the Shortcuts app a few times a day; no app change, no in-app tip.
22. **mine** — A little extra Loop battery for more frequent reads is fine.
23. **mine** — The words in 19 are approved as written.
24. **mine** — Inactivity alert: the owner first checks whether the Loop already buzzes when sitting still; Vesel never opens or depends on Polar Flow.

## Open questions (owner)
1. **Reading at fixed times.** The Loop never asks to be read on a schedule. Set up "Sync Vesel" yourself in the Shortcuts app a few times a day (e.g. 12:00, 16:00, 20:00)? Recommended: yes, no app change.
2. **Reading more often costs a little Loop battery.** Maybe a read every hour or two on a normal day. OK? Recommended: yes; the Syncing page shows how often.
3. **Words**: sync log "your Loop checked in", "long read while charging"; reminder "Time to move" / "Your Loop says you've been still for a while." (silent); iOS's card "Reading your Loop" / "Keeps going if you leave Vesel". OK?
4. **The Loop's own inactivity alert must be on, and only Polar Flow can switch it on.** Opening Polar Flow also sends your Loop's data to Polar's cloud, which Vesel otherwise never does. (a) Check whether the Loop already buzzes when you sit still; if so, nothing to do. (b) Turn it on once in Polar Flow, accepting that upload, then close Polar Flow. (c) Skip stand-up reminders. Recommended: (a) first.

## Deviations
- Phase 1: `SyncGap.isDue` takes `nightOver: Bool` instead of `sleepStatus:`: `SleepRecordingStatus` lives in VeselWearable, and VeselCore imports nothing.
- Phase 1: `held` is saved one day per transaction, as before, not all in one: an unreadable payload keeps the days before it, as it did.
- Phase 1: the fake band's `dropMidway` acts once, on the next read; a lost band (no reconnect) answers again from the next `startSync`.
- Phase 1 (review): drops are also counted in `deviceConnecting` after being connected: with `automaticReconnection` the SDK reports a dropped direct connection only as connecting again, never as `deviceDisconnected`.
- Phase 1: the data rule's store-as-you-go and "an hour apart" lines were written now, since they are true after this phase.
- Phase 2: `runHeld(_:progress:)` takes the read's progress listener instead of the task; the caller's task cancellation stops the read (`bandSync.cancelSync()`), and a read cancelled while still waiting never starts.
- Phase 3: `standUpReminder(alertedAt:)` takes the notice's time; the 5-minute check is `StandUp.isTimely` (VeselCore). `PolarBandEvents` takes the clock for that time. `BandWakeHandler` reads the band's events in one loop that starts the reminder and forwards every event to a second, serial loop, so a read never holds the reminder back.
- Phase 4: I'm up's continued read ends the night inside the task (`SyncPipeline.endSleep`, split out of `endNight`), so a band that won't end the night still shows I'm up's error. Forget this Loop's last read (Loop & settings' only Sync now) also goes through it.
- Phase 4: no Simulator check of iOS's card: the Simulator ran Sync now to "done"; whether through the card or the fallback isn't visible there.
- Phase 2: the long read is also asked for at launch, not only after each long read, so the first one is ever submitted.
- Review: the next long read is asked for when one starts (as the refresh does), not after it ends; its expiry lets the database sleep only if Vesel isn't on screen; `.sleepEnded` / `.syncRequested` wait for any running read (a long read, Sync now) and then read afresh, instead of joining it.

## Verification
- Fast checks (contract): `solidvibes lint . && swift test` for VeselCore (`SyncGapTests`), VeselStorage (`saveReadings`, `MetricsUpdaterTests`), VeselSync, VeselBackupKit.
- Full checks (contract): `xcodebuild test` on the iPhone 17 Pro Max Simulator runs `VeselWearableTests` (the package imports the Polar SDK, so not `swift test`): whole-read rules, drop with and without reconnect, cancel, ClearPlan, inactivity countdown.
- Simulator, `-VeselScenario normal`, `-VeselTab today`: the reading list still ticks heart rate and last night's parts; Loop & settings shows "Stand-up reminders", off.
- Owner-only (real Loop and iPhone):
  - Over a normal day: "your Loop checked in" rows on the Syncing page; Today's steps "read" time within an hour or two. No such rows → the Loop sends none; say so in `band-sync.md`.
  - After a night with the phone charging: a "long read while charging" row lasting over 30 seconds that ended "done".
  - Stand-up (switch on, Loop's alert on): sit still until the Loop buzzes; "Time to move" shows silently. Switch off: nothing.
  - Tap Sync now, leave Vesel at once: iOS shows "Reading your Loop" with progress; later Sync now "done". Same with I'm up. Cancel from the card: "stopped early" or "didn't finish", band storage unchanged.
  - With several days unread (Loop away from the phone for a few days): Sync now, leave Vesel; note whether iOS ends the card before heart rate finishes.
  - After a read ending "stopped early" or "didn't finish", the next one carries on; band storage drops after whole reads.

## Rule gaps
- (end state) `.agents/skills/data/SKILL.md`: "Readings with data are stored as each kind arrives. Empty days, heart-rate and beat-to-beat ledger rows, and clearing only after a whole read: every fetch returned, not cancelled, no Bluetooth drop. The Polar SDK reports a failed file as no data." Also "an hour apart" on the two-empty-reads rule.
- (end state) `.agents/skills/layers/SKILL.md`: never call `setPolarUserDeviceSettings` (it can switch off the band's inactivity alert).
- (end state) `.agents/skills/data/SKILL.md`: the long read and the continued read resume and suspend the database through `BackgroundTime`'s held mode.
- (true now, fixed in this plan's doc edit) `band-sync.md` claimed reads "every 5 minutes" while the app stays open.
