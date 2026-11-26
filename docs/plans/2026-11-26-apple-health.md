---
status: not-started
---

# Apple Health: Vesel writes its readings, one way
**Date**: 2026-11-26
**Status**: Approved
**Touches**: `docs/decisions/2026-11-26-apple-health.md` (new), `docs/decisions/2026-10-26-no-cloud.md`, `AGENTS.md`, `docs/intent.md`, `docs/how-it-works/apple-health.md` (new), `docs/how-it-works/backup.md`, `docs/how-it-works/sleep.md`, `docs/design/screens.md`, `docs/stack.md`, `.agents/skills/data/SKILL.md`, `.agents/skills/layers/SKILL.md`, `.agents/skills/testing/SKILL.md`

## TL;DR
- Two phases, one PR each, built on `feat/workouts` (what the owner's iPhone runs).
- Phase 1: switch, bookkeeping table, writer, and heart rate, resting HR, breathing, sleep, steps.
- Phase 2: HRV as Vesel's own SDNN, active and resting energy, workouts with heart rate and route.
- Migration `v9` adds one table, `health_write` (per day, night or workout: when written, version, fingerprint). Not uploaded.
- The writer lives in `VeselSync` beside the Mac backup (`HealthWriter` + `HealthStore` seam), tested on the Mac with a fake store.
- `HealthKitStore` (app target) is the only code that imports HealthKit.
- What to write comes from pure VeselCore mapping (`HealthMapping`) fed by VeselStorage queries.
- Each sample: Apple's sync identifier + sync version (write time, ms) + `VeselUnit`; rewrite = save new, then delete own older ones of that unit.
- Runs only through `SyncPipeline`, never beside a read: after each read, and on coming to the front once no read runs.
- Skipped while the phone is locked (protected data unavailable); catches up at the next unlocked run.
- Loop & settings gains an "Apple Health" section: one switch and one status line.
- Apple's sheet on turning it on, and again only when a newer Vesel writes a type not yet asked about.
- HRV SDNN: median of per-recording SDNN of clean beats, recordings fully inside sleep; stored as `heart.sdnn` v1.
- Workout sport: the Loop's or yours, else Other (Vesel's guesses change with later workouts, so they aren't written).
- Risk areas: health data to a new place (owner's decision), one migration, deleting Vesel's own copies in Health.

## Context
The owner's app Mira (self-hosted) reads Apple Health. Vesel keeps everything on the phone and the owner's Mac today (`2026-10-26-no-cloud.md`). The owner decided on 2026-11-26 that Apple Health on the phone plus its encrypted iCloud backup is allowed, and what goes in (`docs/decisions/2026-11-26-apple-health.md`). Vesel writes; it never reads.

What the code already gives:
- Resting HR is `computed_metric` `recovery.restingHeartRate` (60 000 ÷ Nightly Recharge `mean_nightly_recovery_rri`), breathing is `recovery.breathing` (60 000 ÷ `mean_nightly_recovery_respiration_interval`, ms → breaths/min); both per night (`RecoveryContributors`, method `recovery` v2).
- Hourly steps come from `raw_export` (kind `activitySamples`) `$.samples`: per-minute `{time: "2026-10-26T06:10:00+01:00", steps}` (`HourlySteps`).
- `activity_day.calories_json` = `{bmr, activity, total}` kcal.
- `sleep_night.phases_json` = `[{secondsFromStart, state}]`, states `wake, rem, light, deep, unknown`. The night key comes from Polar's `sleepResultDate`, so its ledger row may sit on the night or the day after.
- `hr_sample(ts, bpm)`; `ppi_session`/`ppi_sample(ts_ms, interval_ms, error_ms, blocker, skin_contact)`, kept on the phone; `PPICleaning.clean` is the stress cleaning.
- Workouts: `workout` (start/end, calories, `hr_json` = `WorkoutHeartRates{intervalMs, bpm[]}`, 0 = none), `workout_choice` (sport, hidden), `workout_route`. `WorkoutLabel.Source` is `owner, band, speed, timeOfDay, none`; the guesses depend on other workouts and the `workouts.sports` setting. `LabelledWorkout.route?.points` are the route cut to the workout with points under 25 m kept (`WorkoutRouteSummary`); `AppDatabase.route(for:)` is the whole uncut recording.
- `band_ledger.stored_at` is the **start** time of the read that stored it (`fetchStoreAndClear` takes `now` once; heart-rate and PPI rows land earlier through `saveReadings` and get their ledger row at the end with that same start time). So a write that overlaps a read could record a `written_at` later than a `stored_at` it never saw. `SyncPipeline.idle()` waits for a running read (`backUpNow` uses it).
- HealthKit (SDK 27.2 headers): `HKMetadataKeySyncIdentifier` replaces an existing object with the same id when `HKMetadataKeySyncVersion` is greater; `predicateForObjectsWithMetadataKey:operatorType:value:` exists; sleep values `inBed, asleepCore, asleepDeep, asleepREM, awake, asleepUnspecified`; HRV is `heartRateVariabilitySDNN` only (ms); `HKWorkoutBuilder` and `HKWorkoutRouteBuilder` are iOS only, so they stay in the app target. While the phone is locked HealthKit accepts saves (cached, merged at unlock) but queries and deletes fail with `errorDatabaseInaccessible`. `appleSleepingWristTemperature` exists; the header doesn't say who may write it, Apple's docs treat `apple…` types as Apple's own. Not written either way (owner's decision).

## Constraints
- Rules: `.agents/skills/data/SKILL.md`, `.agents/skills/layers/SKILL.md`, `.agents/skills/testing/SKILL.md`; always-on `AGENTS.md` (Non-negotiables: health data stays on the phone, the owner's Mac and now Apple Health with its encrypted iCloud backup; never nag; every number explained; no score to chase).
- Packs: none (`docs/stack.md` has no `## Packs`).
- Skills to load: `writing` and `accessibility` (Phase 1: the settings section and its words); `security-basics` (both phases: health data to a new place). Its step 1, what could go wrong for whom: the owner's health history lands in a store other apps can be allowed to read; Vesel must write only what the decision lists, under true labels, never read Health, never log values, and never touch other apps' data.
- Layers: only `HealthKitStore` (app target, `ios/Vesel/Health/`) imports HealthKit; it also builds `CLLocation` values from stored route points (Phase 2) and never asks for or reads the phone's location. `HealthWriter` and the `HealthStore` protocol live in `VeselSync` (imports VeselCore and VeselStorage only). Mapping is pure VeselCore; queries live in VeselStorage. Screens reach Health only through the settings model's closures; the writer runs only from `SyncPipeline`.
- Data: the phone's database stays the source of truth; Health gets copies. Never log a value or HealthKit errors with sample contents. Every background write runs inside `BackgroundTime` (resume the database first).
- Time from the injected `VeselClock`; never `Date()` in logic (the sync version is the clock's time in ms).
- **Risk — health data sent off the phone:** to Apple Health only, per `2026-11-26-apple-health.md` (mine). Only `HealthKitStore` writes. Types written are exactly the decision's list; share-only authorization, no read types, no `NSHealthShareUsageDescription`.
- **Risk — database migration:** `v9` (next free at build time; rebase and renumber if another lands first, never edit a shipped one) adds `health_write` only. No change to existing tables. Not in `UploadTable`, so the Mac backup and server are unchanged.
- **Risk — deleting data:** Vesel deletes from Health only its own objects, only by `VeselUnit` and an older sync version. Never `deleteObjects` without both.

## Approach

**Units.** Everything Vesel writes belongs to one unit: a day (`heartRate/2026-11-03`, `steps/…`, `energy/…`), a night (`sleep/…`, `restingHeartRate/…`, `respiratoryRate/…`, `hrv/…`) or a workout (`workout/20261103/071000`). A unit is written whole. `health_write(unit PRIMARY KEY, kind, mapping_version, digest, sync_version, written_at)` records the last write. `written_at` is a snapshot taken inside the read transaction that gathers the unit's rows, never the time the save finished.

**What's pending.** A unit is pending when:
- it has data and no `health_write` row (the backfill), or its mapping version changed, or the set of kinds it depends on changed (below), or one of its sources was stored after `written_at`: heart rate and steps — `band_ledger.stored_at` of that day and kind (plus, Phase 2, any workout overlapping the day: `workout.stored_at`, `workout_choice.chosen_at`); sleep — the `sleep` ledger rows of the night and the day after; resting HR, breathing, HRV — that metric's `computed_at` and the sleep stamp; energy — the `dailySummary` ledger row plus the day's workouts; a workout — `stored_at`, `chosen_at`, and `updated_at` of routes overlapping it;
- or it has a `health_write` row and no data now (a metric `MetricsUpdater` dropped, a night that no longer reaches 5 HRV recordings, a hidden workout): an empty batch, so its old copies are removed and its row deleted.

Because the writer never runs beside a read (When, below), every `stored_at` it can see is earlier than its snapshot, and a later read always stamps later. This mirrors `StressUpdater`'s late-reading check. A per-row "written to Health" column on ten tables (like `uploaded_at`) was ruled out (a wide migration, and the upsert would need a second reset), and a single cursor can't retry one unit or skip a kind the owner didn't allow. Newest first, so the latest days land first during the backfill.

**Writing a unit.** VeselStorage gathers the unit's rows and VeselCore's `HealthMapping` turns them into plain `HealthItem`s (kind, start, end, value + unit or category value, sync id; a workout item carries its sport, energy, heart-rate items and route points). Mapping takes the set of allowed kinds, since where a reading goes depends on it (Phase 2). The fingerprint is SHA-256 of the items' canonical encoding plus that set; the device (firmware) is left out, so a firmware update doesn't rewrite history. If the fingerprint matches, only `written_at` moves. Otherwise `version = max(now in ms, last version + 1)`: save every item with `SyncIdentifier`, `SyncVersion = version`, `VeselUnit = unit`; then delete this unit's objects with a lower version (`VeselUnit == unit AND SyncVersion < version`, per HealthKit type of the kind). Same ids replace in place; ids that went are deleted. A crash between save and delete leaves the unit pending, and the redo is harmless. Time-based versions keep rising across a reinstall, so a fresh database never writes under Health's older copies.

**Sync ids.** `vesel.hr.<ts>`, `vesel.restingHR.<night>`, `vesel.breathing.<night>`, `vesel.hrv.<night>`, `vesel.sleep.<night>.inBed`, `vesel.sleep.<night>.<segment start, unix s>`, `vesel.steps.<hour start, unix s>`, `vesel.activeEnergy.<day>`, `vesel.restingEnergy.<day>`, `vesel.workout.<session>`, `….energy`, `….hr.<ms>`, `….route`.

**When.** Only through `SyncPipeline`, never beside a read:
- at the end of every read, after the backup, in the same background time (cancelled on expiry like the backup);
- `SyncPipeline.writeToHealth()` from `AppEnvironment.foreground()` (after its `run(.foreground, onlyIfDue:)`) and once after the switch is turned on: `await idle()` first, then its own `BackgroundTime`, like `backUpNow`.
The pipeline keeps the running write as a stored `Task` and a second call awaits it (like `running`), so two writes never interleave. Before the run and between units, the writer asks `isProtectedDataAvailable` (a closure from the app: `UIApplication.shared.isProtectedDataAvailable`); false → the run stops with everything still pending. `errorDatabaseInaccessible` is mapped to the same outcome as a fallback. So a locked-phone read doesn't save a backlog it can't then tidy, and the next unlocked run (at the latest, opening Vesel) catches up. Background delivery isn't needed.

**Allowed kinds.** `HealthKitStore.authorization()` reports per kind: allowed (every type `.sharingAuthorized`), denied (any `.sharingDenied`), or not asked (any `.notDetermined`). Denied and not-asked kinds are skipped and stay pending, so allowing them later backfills them. When the switch is on and any kind is not asked (a newer Vesel added types, as Phase 2 does), the foreground write calls `requestAuthorization` first: Apple's sheet shows only those new types, once. A run in the background never asks.

**Turning on and off.** Off by default (setting `health.write`). Turning on: `health_write` is cleared (so everything is written again: after a Delete All Data in Health, or a long time off, nothing is missing; same ids, so nothing doubles), `requestAuthorization(toShare: all types, read: [])` (Apple's sheet), store on, write. Off stops writing; nothing is deleted.

**Status.** The writer stores its outcome in the setting `health.lastRun` (time, outcome, days still pending at the end of the run, kinds denied); the settings section observes only that setting and the switch. No query over all history on screen.

**Ruled out:** a cursor or per-table columns (above); relying on the sync version alone (can't remove samples that went); deleting a unit then rewriting (a gap in Health and churn for Mira); counter versions in the database (a reinstall would restart below Health's versions); reading Health to compare (Vesel never reads); background delivery (only for reading); writing Polar's RMSSD as SDNN (decision); Apple's deprecated `addSamples(_:to:)` and `HKWorkout(…totalEnergyBurned:)` (deprecated since iOS 17); a new package for the writer (it's the same "copy out after a read" job as the Mac backup, so it joins `VeselSync`: no new package, no new check).

### Phase 1 — Switch, writer and the simple kinds (heart rate, resting HR, breathing, sleep, steps)
- VeselCore `Health/HealthItem.swift`: `HealthKind` (`heartRate, restingHeartRate, respiratoryRate, sleep, steps` now; `hrv, energy, workout` in Phase 2), `HealthUnit` (kind + key, `"kind/key"`), `HealthItem` (quantity: value + `HealthQuantityUnit` bpm/count/kcal/ms/breathsPerMinute; category: `HealthSleepValue`; workout in Phase 2), `HealthBatch` (unit, items, digest), `HealthMapping.version[kind]` (all 1).
- VeselCore `Health/HealthMapping.swift`: pure builders. Heart rate: each reading at its time. Resting HR and breathing: the metric's value over the night's sleep window; with no sleep row, the night's day from 00:00 to 24:00 in the Nightly Recharge row's offset (`raw_export.utc_offset_seconds` of that night). Sleep: one `inBed` start–end, then consecutive equal phases merged into segments (light → core, deep → deep, rem → rem, wake → awake; unknown left out; before the first phase is awake, as `SleepNight.state(at:)` counts). Steps: per-minute samples parsed with their own offset, summed per real hour (start of the hour in that offset), hours with 0 left out; a repeated hour when clocks go back is two hours; an hour ends at the earlier of its end and its last sample's minute + 60 s, so today's current hour never ends in the future.
- VeselStorage `Migrations.swift` `v9`: `health_write`. `HealthWrites.swift`: `pendingHealthUnits(kinds:limit:)` (newest first, including units with a row and no data), `healthBatch(_ unit:kinds:)` (rows and the `written_at` snapshot in one read transaction), `markHealthWritten(_:digest:version:at:)`, `forgetHealthWrite(_ unit:)`, `clearHealthWrites()`, settings `health.write` and `health.lastRun` (`setting` isn't uploaded), `observeHealthStatus()` (those two settings only).
- `VeselSync`: `HealthStore.swift` (protocol: `authorization()`, `requestAuthorization()`, `save(_ items:unit:version:)`, `removeStale(unit:kind:below:)`, errors `.locked`, `.notAllowed`, `.failed`) and `HealthWriter.swift` (`run(isProtectedDataAvailable:) -> HealthRunOutcome`: `.upToDate`, `.waitingForUnlock`, `.failed`, `.off`; stops between units when cancelled; records `health.lastRun`).
- App `ios/Vesel/Health/HealthKitStore.swift`: maps `HealthItem` → `HKQuantitySample`/`HKCategorySample`, metadata (sync id, version, `VeselUnit`), `HKDevice(name: "Polar Loop", manufacturer: "Polar Electro", model: "Loop", firmware: the band row's, nil without one)`, authorization per kind, error mapping (`errorDatabaseInaccessible` → `.locked`, authorization errors → `.notAllowed`).
- App wiring: `AppEnvironment` builds the store; `SyncPipeline` owns the writer: `writeToHealth()` (idle first, own background time, stored task), the after-read call, cancel in `cancelForExpiry`; `foreground()` calls it and asks for not-yet-asked kinds first.
- Settings: `ios/Vesel/Loop/HealthSection.swift` (like `BackupSection`), between Workouts and Alerts; state and closures in `LoopSettingsModel`. Words below (Screens).
- `ios/project.yml`: entitlement `com.apple.developer.healthkit: true` and `com.apple.developer.healthkit.access: []` (also in `Vesel.entitlements`); `INFOPLIST_KEY_NSHealthUpdateUsageDescription`: "Vesel copies your Loop's readings into Apple Health, so apps you allow there can read them. It never reads from Health." `HKHealthStore.isHealthDataAvailable()` false → the section is hidden.
- Contract: `AGENTS.md` Factory `layers`: `sync:` line widens to "copies out: `VeselSync` → Mac backup (FastAPI route → SQLite) and Apple Health (`HealthWriter` → `HealthKitStore`)". `checks` unchanged (VeselSync is already tested).

### Phase 2 — HRV (SDNN), energy, workouts
- VeselCore `Analysis/NightSDNN.swift` (`heart.sdnn`, method `sdnn` v1): for each PPI session lying entirely inside sleep start–end, `PPICleaning.clean`; it counts with ≥ 60 kept beats and kept ≥ 80 % of its intervals; its SDNN is the sample standard deviation (n − 1) of its kept intervals; the night's value is the median of counted sessions, needing ≥ 5; inputs: sessions counted, sessions inside sleep, kept beats; the explanation text says all of it. Why per recording during sleep: Apple's own SDNN readings are short (about a minute) at rest, so whole-night SDNN (which grows with stage changes) wouldn't compare; the median keeps one restless recording from moving the night.
- VeselStorage: a small `SDNNUpdater` beside `StressUpdater`, not inside the 28-night `MetricsUpdater.recompute` (SDNN has no range). A night is recomputed when a `ppi` or `sleep` ledger row of the night or the day after has `stored_at` at or after the last SDNN pass (setting `sdnn.lastPass`, the snapshot time of the pass), so late beats for an old night count and a night that can't produce a value isn't retried every read. History: a setting `sdnn.fill` (method version + the oldest night done) walks back from today; each pass also takes the next 14 older nights with sleep and moves it back, until it passes the first night. A method version bump starts the walk again. One write transaction per pass, PPI loaded only for those nights' sleep windows. A night that no longer produces a value has its `heart.sdnn` deleted. Called from `MetricsUpdater.updateAfterSync`. Not shown on any screen (its explanation lives in the metric and `apple-health.md`).
- `HealthMapping` energy: resting energy = `bmr` over the day (00:00 → 24:00, today → the `dailySummary` `stored_at`); a workout's active energy = max(0, calories − bmr × duration ÷ 86 400); nil calories → no energy sample and nothing subtracted. The day's active energy = max(0, `activity` − Σ the day's shown workouts' active energy) **only when the workout kind is allowed**; otherwise the whole `activity`. A workout across midnight belongs to its start day (energy and heart-rate exclusion follow its whole time on both days' heart-rate units; energy is subtracted from the start day only).
- `HealthMapping` workouts: hidden → empty batch (old copies removed). Sport only from `WorkoutLabel` sources `owner` or `band`: running, cycling, swimming, traditionalStrengthTraining; a guess or none → other. Heart rate: the workout's `hr_json` (reading i at start + i × interval, 0 left out); none → the 24/7 readings inside it. The heart-rate day unit leaves out 24/7 readings inside shown workouts **only when the workout kind is allowed**. Route: `LabelledWorkout.route?.points` (cut to the workout, under 25 m kept); left out when the route type isn't allowed (the workout kind needs workout, heart rate and active energy types; the route is optional).
- `HealthKitStore`: workout via `HKWorkoutBuilder(configuration: activityType, device)`, `beginCollection(at: start)`, `addSamples` (energy + heart rate, each with sync id, version, `VeselUnit`), `addMetadata`, `endCollection(at: end)`, `finishWorkout`; then `HKWorkoutRouteBuilder.insertRouteData([CLLocation])` (timestamp, coordinate, horizontal accuracy) and `finishRoute(with:metadata:)`. Stale removal covers workout, route, heart rate and active energy types.

### Screens (Phase 1)
Loop & settings, a new section titled **Apple Health**, between **Workouts** and **Alerts**, same card style as the others. Inside: one switch row, **Write to Apple Health**. Under the card, one small muted line (and at most one more), like the notifications line under Alerts. All from `health.lastRun` and the switch:
1. **Off, never written:** "Copies your readings into Apple Health on this iPhone, so apps you allow there can read them. Vesel never reads from Health."
2. **Turning on:** Apple's own Health sheet slides up over Vesel (iOS's list of what Vesel may write, with Turn On All). After an update that adds kinds, the same sheet once on opening Vesel, with only the new ones.
3. **On, writing history or catching up:** "Writing to Apple Health · 42 days to go" (days still pending at the end of the last run; "1 day to go").
4. **On, up to date:** "Up to date · written 9 minutes ago" (the same relative words as "Last read 9 hours ago").
5. **On, nothing to write yet** (no reads yet): "Nothing to write yet. Vesel writes after its first read of your Loop."
6. **On, some kinds not allowed** (second line under 3 or 4): "Not allowed in Health: Sleep, Workouts. Allow them in Health › your profile › Apps › Vesel." (names: Heart rate, Resting heart rate, Breathing rate, Sleep, Steps; Phase 2 adds HRV, Energy, Workouts.)
7. **On, nothing allowed:** "Health isn't letting Vesel write anything. Allow it in Health › your profile › Apps › Vesel." (replaces 3–4; the switch stays on).
8. **On, last write failed** (not the locked case): "Couldn't write to Apple Health. Vesel tries again at its next read." (replaces 4).
9. **Off, after writing:** "What Vesel wrote stays in Apple Health. To remove it: Health › your profile › Apps › Vesel › Delete All Data."
Locked-phone waiting is never shown (the screen can't be seen while locked; it shows as 3). No alert, badge or Today change. VoiceOver reads the switch and the line(s); colour carries nothing.

## Files
Phase 1:
- `ios/Packages/VeselCore/Sources/VeselCore/Health/HealthItem.swift` — new: kinds, units, items, batch, digest, mapping versions.
- `ios/Packages/VeselCore/Sources/VeselCore/Health/HealthMapping.swift` — new: heart rate, resting HR, breathing, sleep, steps builders.
- `ios/Packages/VeselCore/Tests/VeselCoreTests/HealthMappingTests.swift` — new: sleep segments, steps by real hour (clocks going back, today's current hour), resting/breathing windows and fallback, digest stable and without the device.
- `ios/Packages/VeselStorage/Sources/VeselStorage/Migrations.swift` — `v9` `health_write`.
- `ios/Packages/VeselStorage/Sources/VeselStorage/HealthWrites.swift` — new: pending units, batches, mark, forget, clear, status settings.
- `ios/Packages/VeselStorage/Tests/VeselStorageTests/HealthWritesTests.swift` — new: backfill all; late reading makes a day pending; a ledger row stamped earlier than a write that saw it stays not pending, one from a later read is pending; same data not pending after mark; mapping version bump; a unit whose metric went is pending with an empty batch; clear makes everything pending; migration.
- `ios/Packages/VeselSync/Sources/VeselSync/HealthStore.swift` — new: protocol and errors.
- `ios/Packages/VeselSync/Sources/VeselSync/HealthWriter.swift` — new: the run loop.
- `ios/Packages/VeselSync/Tests/VeselSyncTests/HealthWriterTests.swift` — new, fake store: backfill; protected data unavailable stops with everything pending, next run writes it; denied and not-asked kinds stay pending; a rewrite saves then removes stale; an empty batch removes and forgets; unchanged skips; cancel; `health.lastRun` written.
- `ios/Vesel/Health/HealthKitStore.swift` — new: the only HealthKit code.
- `ios/VeselAppTests/HealthKitStoreTests.swift` — new (Simulator): item → HK object types, units, metadata, device; error mapping.
- `ios/Vesel/AppEnvironment.swift` — build the store; foreground write and new-kind ask.
- `ios/Vesel/Background/SyncPipeline.swift` — `writeToHealth()` (idle, background time, stored task), after-read call, cancel on expiry.
- `ios/VeselAppTests/SyncPipelineTests.swift` — the write never starts while a read runs; two calls don't interleave.
- `ios/Vesel/Loop/HealthSection.swift` — new: the section.
- `ios/Vesel/Loop/LoopSettingsModel.swift`, `ios/Vesel/Loop/LoopSettingsView.swift` — status, switch (clear + ask + write), place the section.
- `ios/VeselAppTests/LoopSettingsModelTests.swift` — status words per state.
- `ios/project.yml`, `ios/Vesel/Vesel.entitlements` — HealthKit entitlement, usage string.
- `AGENTS.md` — Factory `layers` line.
- `docs/stack.md` — code layout (`VeselSync`: Mac backup and Apple Health), the "Analytics" row's "No data leaves the phone except to the owner's Mac" gains "and Apple Health".
- `docs/design/screens.md` — Loop & settings: the Apple Health section.
- `docs/how-it-works/apple-health.md` — Planned → Built for Phase 1's kinds.
- `docs/how-it-works/backup.md` — `health_write` is not sent.
- `.agents/skills/data/SKILL.md`, `.agents/skills/layers/SKILL.md`, `.agents/skills/testing/SKILL.md` — see Rule gaps.
- `CHANGELOG.md` — one sentence.

Phase 2:
- `ios/Packages/VeselCore/Sources/VeselCore/Analysis/NightSDNN.swift` — new.
- `ios/Packages/VeselCore/Tests/VeselCoreTests/NightSDNNTests.swift` — new: written-out numbers; flagged beats, a session crossing sleep start, too few sessions.
- `ios/Packages/VeselStorage/Sources/VeselStorage/SDNNUpdater.swift` — new; `MetricsUpdater.swift` calls it.
- `ios/Packages/VeselStorage/Tests/VeselStorageTests/SDNNUpdaterTests.swift` — new: late PPI for an old night recomputes; a night without enough recordings isn't retried each read; history in batches.
- `ios/Packages/VeselCore/Sources/VeselCore/Health/HealthItem.swift`, `HealthMapping.swift` — hrv, energy, workout items; heart rate and energy move to the workout only when workouts are allowed.
- `ios/Packages/VeselCore/Tests/VeselCoreTests/HealthMappingTests.swift` — energy split (allowed and not), nil calories, workout across midnight, guessed sport → other, hidden workout, route optional.
- `ios/Packages/VeselStorage/Sources/VeselStorage/HealthWrites.swift` — workout and energy sources and stamps.
- `ios/Packages/VeselStorage/Tests/VeselStorageTests/HealthWritesTests.swift` — a workout choice makes the workout, its days' heart rate and energy pending; allowing workouts later makes those day units pending.
- `ios/Vesel/Health/HealthKitStore.swift` — workout and route builders.
- `ios/VeselAppTests/HealthKitStoreTests.swift` — workout configuration, route locations.
- `docs/how-it-works/apple-health.md`, `docs/how-it-works/sleep.md` (HRV for Health is SDNN, not shown), `.agents/skills/layers/SKILL.md` (CoreLocation exception), `CHANGELOG.md`.

## Steps
Phase 1:
1. VeselCore items and mapping with tests.
2. Migration `v9` and `HealthWrites` with tests (in-memory database, the fake band's fixtures).
3. `HealthStore` and `HealthWriter` in VeselSync with fake-store tests.
4. `HealthKitStore` and its Simulator tests; entitlement and usage string in `project.yml`.
5. Wire `SyncPipeline` and `AppEnvironment` (after read; foreground after idle; expiry; protected data; new-kind ask); pipeline tests.
6. Health section in Loop & settings with its states; model tests; `#Preview` per state.
7. Docs, rules, contract line, changelog; run the full checks; drive the Simulator flow (Verification).

Phase 2:
1. `NightSDNN` and `SDNNUpdater` with tests.
2. Energy and workout mapping; tests.
3. Workout and energy stamps in `HealthWrites`; tests.
4. `HealthKitStore` workout and route; Simulator tests.
5. Docs, rules, changelog; full checks; Simulator flow including "Not a workout".

## Decisions
1. Apple Health on the phone plus its encrypted iCloud backup is allowed; new decision file, `no-cloud` superseded in part. — **mine** (2026-11-26)
2. Written: heart rate, resting HR, sleep with stages, breathing, hourly steps, active and resting energy, workouts (sport, time, calories, heart rate, route). — **mine**
3. HRV: Vesel's own SDNN from PPI, never RMSSD as SDNN. — **mine**
4. Backfill all history, then keep current. — **mine**
5. Loop first in Health's Data Sources for Steps, Active Energy and Resting Energy, set by the owner; no code. — **mine** (steps); energy added by the agent, same step
6. Not written: skin temperature, stress, recovery. — **mine**
7. SDNN window: per-recording SDNN of clean beats, recordings fully inside sleep, ≥ 60 clean beats and ≥ 80 % kept, median over ≥ 5. — **agent's** (changing it later is a method version bump that rewrites history in Health; easy)
8. One bookkeeping table `health_write` keyed by unit, not a column per table or a cursor. — **agent's**, **hard to undo** (a migration)
9. Rewrite = save with a time-based sync version, then delete own objects of the unit with a lower version. — **agent's**, **hard to undo** in effect (the ids and `VeselUnit` live in Health; changing the scheme later means deleting and rewriting everything Vesel wrote)
10. Sync id scheme as listed in Approach. — **agent's**, **hard to undo** (same reason)
11. Workout active energy = Polar calories − resting share; the day's active energy reduced by it when workouts are allowed. — **agent's**
12. Readings inside a shown workout go with the workout (its own readings, else the 24/7 ones) when workouts are allowed; otherwise they stay on the day. — **agent's**
13. Resting HR and breathing span the sleep window (else the night's day in the recharge row's offset). — **agent's**
14. Steps per real hour in the sample's own offset; the current hour ends at its last minute. — **agent's**
15. Unknown sleep stretches are left out, not written as "asleep". — **agent's**
16. Switch off by default; turning on clears the bookkeeping and writes everything again; off never deletes. — **agent's**
17. Apple's sheet on turning on, and on opening Vesel only when a kind was never asked (after an update). — **agent's**
18. Writer in `VeselSync` beside the Mac backup; HealthKit only in the app target (`HKWorkoutBuilder` is iOS only). — **agent's**
19. Writes only through `SyncPipeline`, never beside a read, and only while protected data is available. — **agent's**
20. Workout sport only from the Loop or the owner; Vesel's guesses are written as Other. — **agent's**
21. Every sample names the Polar Loop as its device; the device isn't in the fingerprint. — **agent's**
22. Newest first during the backfill. — **agent's**
23. Phases: 1 = switch, writer, simple kinds; 2 = HRV, energy, workouts. — **agent's**

## Verification
- Contract `checks` (fast and full); CI green.
- Package tests: mapping numbers written out (sleep segments, steps per hour, energy split, SDNN on a synthetic session with a known SD); pending detection after a late read, a workout fix, a mapping bump, data that went, a switch-on clear; a ledger row from a read that started before the write's snapshot is seen, one from after is pending; writer: protected data unavailable stops with everything still pending, then the next run writes it; denied and not-asked kinds wait; a rewrite removes the old ids.
- Simulator (per `run`, scenario `normal`): open Loop & settings, turn on, allow all in Apple's sheet; wait for "Up to date"; open the Health app in the Simulator: heart rate, resting HR, respiratory rate, sleep stages, steps by hour (Phase 2: HRV, energy, a workout with heart rate) from Vesel with device "Polar Loop". Mark the fake workout "Not a workout": it disappears from Health and its heart rate shows on the day. Turn the switch off: line 9, data stays; on again: nothing doubles. Screenshot each settings state.
- That the stale delete by `SyncVersion` predicate removes exactly the old ids is checked in the Simulator flow above; if HealthKit rejects that predicate, query own objects by `VeselUnit` and delete those with a lower version (same result).
- **Owner only (real iPhone):** after a locked-phone night, nothing is written until the phone is unlocked and Vesel runs, then it catches up once (no repeated saves while locked); a backfill of all history finishes; after the Phase 2 update, opening Vesel shows Apple's sheet once with the new types; Mira sees the data; Loop set first for Steps, Active Energy and Resting Energy in Health's Data Sources; today's resting energy in Health looks like Polar's (whether Polar's BMR for today is so far or the whole day is not known); Polar's day activity calories include its workouts (else the split under-counts); a workout route shows in Health/Fitness.

## Rule gaps
To apply when the code lands (end-state, not yet true):
- `data`: health data leaves the phone only to the owner's Mac and to Apple Health (`HealthKitStore`, per `2026-11-26-apple-health.md`); Vesel never reads Health; deletes only its own objects by `VeselUnit` and older sync version; writes run only through `SyncPipeline` after `idle()` and only with protected data available; `health_write` is bookkeeping, not uploaded; never log values or HealthKit samples.
- `layers`: HealthKit only in `ios/Vesel/Health/HealthKitStore.swift`; `VeselSync` holds the writer and the `HealthStore` seam (copies out: Mac backup and Apple Health); CoreLocation also in `HealthKitStore`, only to build `CLLocation` from stored points.
- `testing`: Health mapping and the writer are tested on the Mac with a fake `HealthStore`; only `HealthKitStore` is tested in the Simulator.
- Contract: the `layers` line in `AGENTS.md` (in the Phase 1 PR).
