---
status: implemented
---

# Exemplar polish: open-source licence, CI, testable app, calm read errors, previews
**Date**: 2026-10-31
**Status**: Implemented 2026-11-01
**Touches**: `docs/decisions/2026-10-28-open-source.md`, `docs/how-it-works/storage-problems.md` (new, Planned), `docs/design/screens.md`, `.agents/skills/layers/SKILL.md`, `.agents/skills/testing/SKILL.md`, `AGENTS.md` (`## Factory` checks), `CONTRIBUTING.md`, `README.md`, `CHANGELOG.md`

## TL;DR
- Eight phases, one PR each, in order: A1 licence + docs → A2 CI → B packages → C1 app start → C2 model seams → C3 read errors + model tests → D previews → E format.
- A1: PolyForm Noncommercial → Apache 2.0, NOTICE file, new decision; CLA stays (rights to the UG). 31 dead plan paths in 23 docs removed.
- A2: GitHub Actions on PRs and `main`: solidvibes lint, Swift package tests, iOS app tests, Mac app build, server pytest. No secrets.
- B: fake band + 4 MB fixtures move to a `VeselWearableTesting` product compiled only in Debug (`VESEL_FAKE_BAND`); Release strips its bundle (build guard + CI step).
- B: package crash points become thrown errors (`as!`, `result!`, `DayKey(…)!`, calendar `!`, fake `try!`).
- C1: the app opens with a calm "can't open your data" screen instead of crashing when the database won't open. Never offers to delete. Retries by itself once the phone is unlocked, also in the background.
- C1: `AppEnvironment` split: `AppRouter` (taps, widget links), `ShortcutSync`, `LaunchOptions` and Simulator set-up in their own files.
- C1: test target `VeselWidgetsTests` → `VeselAppTests`; the 4 `MainActor.assumeIsolated` sites get a one-line why.
- C2: every screen model takes only what it uses (database, clock, units…), like `SyncingModel` already does. Views stay the composition layer: they get `AppEnvironment` from their parent and hand each model its parts.
- C2: DB observations leave `RootView` and `HeartRatePage` for models; the band data report goes through `SyncPipeline`.
- C3: a read that fails shows one calm "Couldn't show this · Try again" card instead of a skeleton forever; a database paused in the background is not an error.
- C3: model tests for Today, Body, Journal, Pairing, Loop & settings, plus the read-problem state.
- D: `#Preview` for every screen and widget, from one shared in-memory database filled once with the fake band's records (no sync pipeline).
- E: `.swift-format` config, one mechanical format commit, CI format check. Last, so it doesn't collide with other branches.
- Lands after calmer-morning phase 1; calmer-morning phases 2–3 build on top of C.

## Context

The owner is making `solidvibes/vesel-health` public as open source and wants it to read as an exemplar. Two reviews of `main` (fe3a832) found the gaps below; each was checked against the code on 2026-10-31.

| Finding | Checked |
|---|---|
| No previews | `#Preview` count in `ios/`: 0. 67 files hold SwiftUI views. |
| One concrete container everywhere | `AppEnvironment` (311 lines) referenced in 36 files; 10 `*Model.swift` inits plus 5 view-file models take it whole. Only `SyncingModel` is built from narrow parts and tested (`SyncingModelTests`). The app test target is named `VeselWidgetsTests` but tests the app (`MeaningTests`, `SyncPipelineTests`, `SyncingModelTests`, `WidgetShotsTests`). `AppEnvironment` also holds routing (`open(_ url:)`, `tabRequest`), the Shortcut's logic (`shortcutSync`), Simulator set-up, and `LaunchOptions` (20 fields). DB observations in views: `RootView.swift:159` (first day), `:167` (band battery), `Pages/HeartRatePage.swift:48` (latest heart rate). `Loop/BandDataReportView.swift:44` reads `environment.bandSync.isStreaming` directly (layers rule: only through `SyncPipeline`). |
| Silent read failures | 24 `catch {}` in 13 files (models, `RootView`, `DayCalendar`, `WeekStrip`, `SyncingView`, `HeartRatePage`, `UnitsStore`); 47 `try?` in `ios/Vesel`. A failed observation leaves the skeleton up forever. |
| Fake band ships in Release | `FakeWearableSource` and `FakeScenario` are `public` in `VeselWearable`, with `resources: [.copy("Resources/Fixtures")]` (7 files, 4.0 MB). The app links `VeselWearable`, so both ship. |
| Crash points | `AppDatabase.swift:8` `as! String`, `:27` `preconditionFailure`, `:59` and `WidgetSnapshot.swift:97` `result!.get()`, `PinnedSession.swift:28` `as! HTTPURLResponse`, `DayKey.swift:17` `parts.year!`, `UsualBedtime.swift:21` `parts.hour!`, `DayKey(night)!` in `SleepNightRecord`, `NightlyRechargeRecord`, `BandDataRecords`; `FakeWearableSource.swift:267–306` `try!`/`as!`; `AppDelegate.swift:14` `fatalError` when the database won't open. `MainActor.assumeIsolated`: `BackgroundScheduler.swift:17,32`, `SyncPipeline.swift:236`, `ContinuedRead.swift:49`. |
| No CI | No `.github/`. `swift-format` ships with Xcode (`xcrun swift-format`); no config. 1208 Swift lines are over 120 characters. |
| Licence and links | `LICENSE` is PolyForm Noncommercial 1.0.0, also named in `README.md`, `CONTRIBUTING.md`, `THIRD_PARTY_NOTICES.md` and `docs/decisions/2026-10-28-open-source.md` (which also still says `stojanovventures/vesel-health`). No licence text in the iOS or Mac app (Loop & settings credits Polar only). 31 references to plan files that aren't in this repo, in 23 files (not 9). |

**calmer-morning conflict.** `feat/calmer-morning` (11 commits, phase 1 and 1b built, phases 2–3 not started) changes `AppEnvironment.swift`, `TodayModel.swift`, `JournalModel.swift`, `BandDataReportView.swift`, `SyncPipeline.swift`, `SyncStatusStore.swift`, `FakeWearableSource.swift`, and adds `ios/VeselWidgetsTests/Support.swift`. Phases B, C1, C2 move or rewrite each of these. **Recommended order:** merge calmer-morning phase 1 first (built; only the owner's iPhone check is open), then exemplar B–E rebased on it (A1 and A2 can land any time); build calmer-morning phases 2–3 after C2, on the new seams (phase 2's "tap opens the Sleep page" goes into `AppRouter`). A1 and A2 touch no app Swift.

## Constraints
- Rules: `AGENTS.md` (always-on), `.agents/skills/layers/SKILL.md` (B–D), `.agents/skills/testing/SKILL.md` (B, C3), `.agents/skills/data/SKILL.md` (B, C1, C3: the database, App Group, observations).
- Packs: none (`docs/stack.md` has no `## Packs`).
- Skills to load: `writing` (A1 docs, C1 and C3 wording), `accessibility` (C1 recovery screen, C3 card), `security-basics` (A2: CI on a public repo; C1: what the recovery screen shows).
- Layers: `VeselCore` no I/O; `VeselStorage` depends on VeselCore only; only `VeselWearable` imports PolarBleSdk (`VeselWearableTesting` must not); `ios/Vesel/Theme/` views take plain values (they are compiled into the widget extension); screens reach the band only through `SyncPipeline`.
- Never log health values, tokens or errors that could carry them. The recovery screen and read card show no error text from SQLite.
- Testing: in-memory GRDB, `FixedClock`, the fake band; never `Date()` in logic; fixtures stay synthetic.
- Risk areas touched:
  - **Database open** (C1): changes what happens when it fails. No migration, no schema change. The recovery screen never deletes or resets anything.
  - **Background entry points** (C1): BGTask handlers must still register before launch ends, even when the database can't open; they then finish the task as failed. A background launch before the first unlock (the database is `completeUntilFirstUserAuthentication`) must recover by itself when the phone unlocks, or Vesel stops working in the background until it is opened.
  - **Secrets** (A2): CI uses no secrets, `permissions: contents: read`, actions pinned to commit SHAs, no `pull_request_target`.
  - Not touched: data leaving the phone, the phone ↔ Mac certificate/token, migrations, deleting data, pairing/factory reset (Pairing gets tests only).

## Approach

**Licence (A1).** Apache 2.0 text verbatim from apache.org as `LICENSE`; a short `NOTICE` (Apache §4(d)) with the copyright line and a pointer to `THIRD_PARTY_NOTICES.md`. No per-file headers (Apache doesn't need them; less noise). CLA unchanged in substance: contributions still transfer to the UG, plus one sentence that Vesel is published under Apache 2.0 and that this agreement applies to contributions instead of Apache 2.0 §5. `NOTICE` says Apache 2.0 covers Vesel's own code and the Polar BLE SDK stays under Polar's licence. A new decision `2026-10-31-apache-licence.md` supersedes only the licence bullet of `2026-10-28-open-source.md`; that file gets its repo line fixed and a "Licence superseded by …" pointer. Dead plan paths: delete the path, keep the words (`docs/README.md` already says older plans aren't in this copy). Ruled out: MIT (no patent grant, no NOTICE handling), keeping PolyForm (owner decided).

**CI (A2).** One workflow, `.github/workflows/checks.yml`, on `pull_request` and `push` to `main`, `concurrency` cancels stale runs. Jobs run in parallel:
| Job | Runner | Runs |
|---|---|---|
| lint | `ubuntu-latest` | clone `solidvibes/solid-vibes` (public, MIT) at a pinned commit; `bash solid-vibes/bin/solidvibes lint .` |
| packages | `macos-26`, newest Xcode on the image | `swift test` VeselCore, VeselStorage, VeselSync |
| backup-kit | `macos-27` if the image exists | `swift test` VeselBackupKit (its package needs macOS 27 to run) |
| ios | `macos-26`, Xcode 27 if present | `brew install xcodegen`; `xcodegen generate`; `xcodebuild test` on an iPhone Simulator; from B on, a Release device build with `CODE_SIGNING_ALLOWED=NO` |
| mac | `macos-26`, Xcode 27 if present | `xcodegen generate`; `xcodebuild build` (building for macOS 27 needs only the macOS 27 SDK, so Xcode 27; without it the job is left out) |
| server | `macos-26` | `astral-sh/setup-uv`; `uv run pytest` (`setup.sh` uses `scutil`, `shasum`: macOS only) |
SPM caches keyed on `Package.resolved`. CI's Simulator is `name=iPhone 17 Pro Max,OS=latest` because the runner may not carry iOS 26.5; the contract's local check keeps 26.5. CI is therefore close to, not the same as, the contract's full checks; `AGENTS.md` says exactly what it runs. Ruled out: one big job (slow, one failure hides others), Xcode Cloud (needs Apple account set-up and secrets).

**Fake band out of Release (B).** New target and product `VeselWearableTesting` in the `VeselWearable` package: `FakeWearableSource`, `FakeScenario`, `FakeFailure`, `FakeBandError` and `Resources/Fixtures`. `VeselWearableTests` and the app tests depend on it. The app links it (Xcode can't link a package product per configuration). Dead-stripping alone won't drop it (package targets link whole and Swift type metadata survives), so the target compiles to nothing in Release: `swiftSettings: [.define("VESEL_FAKE_BAND", .when(configuration: .debug))]` and every source in it is wrapped in `#if VESEL_FAKE_BAND`. App code uses it only under `#if DEBUG`. A Release-only post-build script in `ios/project.yml` ("Leave the fake band out of Release") removes `VeselWearable_VeselWearableTesting.bundle` from the built app and fails the build if the binary still contains the string `FakeWearableSource`. XcodeGen turns user-script sandboxing on by default, so the `Vesel` target sets `ENABLE_USER_SCRIPT_SANDBOXING: NO` (as `mac/project.yml` already does); the script only touches the built `.app`. CI builds Release for `generic/platform=iOS` so the guard runs on every PR. Ruled out: a second app target (doubles build time, two Info.plists), reading fixtures from the Mac's disk in the Simulator (brittle, breaks previews), `EXCLUDED_SOURCE_FILE_NAMES` on a package product (not reliable for package resource bundles).

**Crash points (B).** Each becomes a thrown error or a non-optional API:
- `AppDatabase.appGroup`: `static var appGroup: String?`; `shared()` throws `StorageError.noAppGroup` when it or the container is missing (replaces `as!` and `preconditionFailure`; same in `WidgetSnapshot`).
- `result!.get()` (2×): `guard let result else { throw StorageError.notOpened }`.
- `PinnedSession.send`: `guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }`.
- `DayKey(_:in:)` and `UsualBedtime`: `calendar.component(.year, from:)` etc. (non-optional), no `!`.
- Records: `DayKey(stored:) throws` in VeselStorage (`StorageError.badDay`); `SleepNightRecord.model()` already throws; `NightlyRechargeRecord.model` and `BandDataRecords` become throwing, callers already sit in throwing reads.
- `FakeWearableSource` shaping helpers throw; `init` already throws.
- `FakeWearableSource.fixtureZone`'s `TimeZone(identifier:)!` and `PolarMapping.swift:270` stay: fixed constant inputs; a one-line comment each.

**App start (C1).** `AppEnvironment` keeps wiring (the layers rule names it) but gets a designated `init(database:band:clock:launch:defaults:)` and `static func live() throws -> AppEnvironment` (opens the shared database, picks the fake band under `#if DEBUG && targetEnvironment(simulator)`, else Polar). Out of it:
- `AppRouter` (`@Observable`, `ios/Vesel/AppRouter.swift`): `tabRequest`, `open(_ url:)`, `openToday()`.
- `ShortcutSync` (`ios/Vesel/Intents/ShortcutSync.swift`): the Shortcut's sync and `ShortcutResult`, built from pipeline, database, clock.
- `LaunchOptions` (`ios/Vesel/LaunchOptions.swift`), unchanged fields; `ShiftedClock` with it.
- `SimulatorSetup` (`ios/Vesel/SimulatorSetup.swift`, `#if DEBUG && targetEnvironment(simulator)`): today's `prepareSimulator`.
- `AppStartup` (`ios/Vesel/AppStartup.swift`, `@MainActor @Observable`): `environment: AppEnvironment?`, `problem: StorageProblem?`, `retry()`. `AppDelegate` builds it (no `fatalError`), registers BGTask handlers through it always, and adds it as the App Intents dependency. With no environment: BGTask handlers finish the task as failed; the Shortcut says "Open Vesel first."; notification and URL taps do nothing. `AppStartup` retries by itself on `UIApplication.protectedDataDidBecomeAvailableNotification` (first unlock after a reboot) and when the scene becomes active; on success, in the foreground or the background, it runs the launch work once (`didFinishLaunching`: units, paired check, wake handler, band connect). Without this, a Bluetooth restoration or BGTask launch before the first unlock would leave the process up with no band connection until the owner opens Vesel.
- `StorageProblemView` (`ios/Vesel/StorageProblemView.swift`): shown by `VeselApp` instead of `RootView` when `problem` is set. `StorageProblem` maps `StorageError.newerSchema` → `.olderApp`, `.noAppGroup` → `.setUp`, anything else → `.couldNotOpen`. Words below (C1 Decisions). "Try again" calls `retry()`; on success `RootView` appears and `didFinishLaunching` runs. No delete, no reset, no error text.

**Model seams (C2).** Follow `SyncingModel`: each model's `init` takes only the concrete parts it uses: `AppDatabase` (tests use `AppDatabase.inMemory()`), `any VeselClock`, `UnitsStore`, `SyncStatusStore`, `DaySelection`, `UserDefaults` (Today), and plain closures for app actions (`didPair: () -> Void`, `sync: (SyncTrigger) async -> Void`). No protocols over the database: the in-memory database is the seam the testing rule already names. Views stay the composition layer: they keep `let environment: AppEnvironment` from their parent and build their model in `init` (`_model = State(initialValue: TodayModel(database: environment.database, clock: environment.clock, …))`), as today. One pattern everywhere; no models created later in `.task`, no wrapper views. SwiftUI's `@Environment` can't be read in `init`, which is where these views build their models, so it is not used for this. `RootView` takes `AppRouter` the same way. New `RootModel` owns first-day and band-battery observations; `HeartRateDaysModel` gains the latest-reading observation; `SyncPipeline` gains `bandDataReport(from:through:)` and `isStreaming` for the Debug report. Ruled out: one protocol per service (more types, no test gain over the in-memory database), a DI framework (stack says no extra dependencies), `@Environment(AppEnvironment.self)` in views (unreadable in `init`; would force optional models or a wrapper view per screen).

**Read problems (C3).** Each screen model that observes gets `private(set) var readProblem = false`; its observe loops `catch` into one shared helper that sets it, except for cancellation and a paused database. A paused database (Vesel suspends it in the background; GRDB then interrupts running reads with `SQLITE_INTERRUPT` and refuses new ones with `SQLITE_ABORT` and its "suspended" message) is told apart by `AppDatabase.isPaused(_ error:)` in VeselStorage, so the app never imports GRDB. It matches `SQLITE_INTERRUPT`, or `SQLITE_ABORT` only with GRDB's suspension message; any other abort is a real problem. An observation that simply waits while paused needs nothing. The flag clears when observing restarts. Views show one `ReadProblemCard` (Theme, plain values, built on `ErrorCard`) in place of the skeleton, with "Try again", which bumps an `attempt` field in `ObserveKey` so `.task(id:)` restarts. One card per screen, not per section ("never nag"). Helpers with no screen of their own keep their last value and no card, and restart when Vesel comes to the front: `RootModel`'s first day and battery run in `.task(id:)` keyed on scene phase (`ObserveKey.active`), like the pages; `AppEnvironment` keeps the units task and restarts it in `foreground()` when it has ended. The 47 `try?`: each is kept (best-effort by design: sleeps, notification asks, Simulator set-up), or turned into a handled error where it hides a read or a save the owner waits on (`AboutYouModel`, `LoopSettingsModel`, `PairingModel` saves). The coder lists the outcome per file in the PR.

**Previews (D).** `ios/Vesel/Preview/PreviewEnvironment.swift` (`#if DEBUG`): `AppEnvironment` on `AppDatabase.inMemory()`, `FakeWearableSource(scenario:)`, `FixedClock` at 2026-10-25 15:00 in `FakeWearableSource.fixtureZone`, `LaunchOptions` with nothing set. One shared database per scenario, filled once (a static async-once `Task`): it fetches each kind from `FakeWearableSource` and writes it with the same VeselStorage calls `BandSync` uses to store payloads, then the analysis updates the pipeline runs after a read (the coder names them from `BandSync`/`SyncPipeline`). No `SyncPipeline`, so no notifications, `BackgroundTime`, widget reloads or backup. `PreviewHost(scenario:)` awaits it and hands the environment to its content. Screen previews (`#if DEBUG`) per state that matters: normal, first day (`.firstDay`), unpaired (`.pairing`), read problem. Widget previews use `WidgetSamples`. Theme previews use plain values only. Views take the environment as today, so a preview passes `PreviewEnvironment`'s environment into the view's `init`.

**Format (E).** `.swift-format` at the repo root: indentation 4, `lineLength` 160, `respectsExistingLineBreaks: true`, `lineBreakBeforeEachArgument: false`, the default rules with `NeverForceUnwrap`/`NeverUseForceTry` off (B removed the ones that matter; the rest are justified constants). `AlwaysUseLowerCamelCase` can't be turned off per file: it stays on; if it flags names, it is turned off globally (recorded in the PR). `OrderedImports` stays on, so the format commit may also reorder imports. Files come from git, never a directory walk (which would enter `Packages/*/.build/checkouts`, `ios/build*/`, `mac/build/`): `git ls-files -z '*.swift' | xargs -0 xcrun swift-format format -i --parallel`, one commit with nothing else in it. CI (a macOS job) and the contract's fast checks add `git ls-files -z '*.swift' | xargs -0 xcrun swift-format lint --strict`. Last so the format diff doesn't collide with calmer-morning or B–D.

## Phase A1 — licence and docs
Size: ~31 files, docs only, no Swift. 3 steps.

### Files
- `LICENSE`: Apache License 2.0 verbatim.
- `NOTICE` (new): "Vesel. Copyright 2026 Stojanov Ventures UG (haftungsbeschränkt), published under its Solid Vibes brand." + "The Apache License 2.0 covers Vesel's own code. The Polar BLE SDK is not part of this repository and stays under Polar's licence (see `THIRD_PARTY_NOTICES.md`)."
- `README.md`: Licence section → Apache 2.0, drop "source-available" and the commercial-licence line; keep the Required-Notice wording as the copyright line; link `NOTICE`.
- `CONTRIBUTING.md`: Licence and CLA → Apache 2.0.
- `CLA.md`: one sentence: Vesel is published under Apache 2.0; for contributions, this agreement applies instead of Apache 2.0 §5. Keep "not yet reviewed by a lawyer".
- `THIRD_PARTY_NOTICES.md`: first line → Apache 2.0.
- `CHANGELOG.md`: "Vesel is now open source under the Apache 2.0 licence."
- `docs/decisions/2026-10-31-apache-licence.md` (new): mine; supersedes the licence bullet of 2026-10-28; CLA and owner unchanged; "what it means": anyone may use, change and sell copies, a version once published stays Apache.
- `docs/decisions/2026-10-28-open-source.md`: repo line → `solidvibes/vesel-health`; licence bullet points to the new decision; drop the `**Plan:**` path.
- `docs/README.md`: "Right now" → licence switch.
- Dead plan paths (remove the path, keep the words): `docs/how-it-works/{meanings,band-sync,sleep,widgets,what-helps,recovery,fitness-age,days}.md`, `docs/decisions/{2026-10-28-units-and-waist,2026-10-28-reading-and-first-week,2026-10-28-range-lines,2026-10-27-night-stress-strip,2026-10-27-day-calendar,2026-10-28-what-helps,2026-10-27-night-tab,2026-10-28-today-journal-body,2026-10-27-in-range-rings,2026-10-27-no-score-to-chase,2026-10-26-mac-app-runs-backup}.md`, `docs/plans/2026-10-26-mac-backup-app.md`.

### Steps
- [x] 1. Write the decision file, then `LICENSE`, `NOTICE`, `README.md`, `CONTRIBUTING.md`, `CLA.md`, `THIRD_PARTY_NOTICES.md`, `CHANGELOG.md`, `docs/README.md`. Fix `2026-10-28-open-source.md`.
- [x] 2. Remove the 31 dead plan paths. Re-run the grep from Verification until it prints nothing.
- [ ] 3. `solidvibes lint .`; open the PR. (Lint passes; the PR opens when the branch is pushed.)

### Verification
- `grep -rnoE "plans/[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+\.(md|html)" docs README.md CONTRIBUTING.md AGENTS.md .agents CHANGELOG.md` → each hit exists in `docs/plans/`.
- `grep -rni "polyform\|noncommercial\|source-available" . --exclude-dir=.git --exclude-dir=plans --exclude=CHANGELOG.md` → only the 2026-10-28 decision's history line and the new decision.
- `solidvibes lint .` passes.
- **Owner only:** read the decision and the CLA sentence; lawyer review of the CLA still before the first outside contribution.

## Phase A2 — CI
Size: 3 files. 4 steps.

### Files
- `.github/workflows/checks.yml` (new): the jobs in Approach.
- `AGENTS.md` `## Factory` `checks`: one line saying exactly what CI runs: "CI (`.github/workflows/checks.yml`, every PR and `main`): solidvibes lint, `swift test` for VeselCore, VeselStorage, VeselSync (and VeselBackupKit when a macOS 27 runner exists), the app's `xcodebuild test` on `iPhone 17 Pro Max, OS=latest`, the Mac app build, `uv run pytest`. It is not a substitute for the local full checks." Adjust to what actually ships.
- `CONTRIBUTING.md`: Checks section says CI runs the list above on every pull request, and how `solidvibes lint` is fetched there.

### Steps
- [x] 1. Look up the runner images' Xcode paths (github.com/actions/runner-images, `macos-26` and `macos-27` READMEs) and the latest `solidvibes/solid-vibes` commit; pin both and every action by SHA.
- [x] 2. Write `checks.yml`. `xcode-select -s` to the newest Xcode 27.x on the image; if the image has none, the newest Xcode it has, and leave out the jobs that need the macOS 27 SDK (mac build) with a comment. If no `macos-27` image exists, leave the backup-kit job out, with a comment in the workflow and a line in CONTRIBUTING ("VeselBackupKit tests run locally only until GitHub has a macOS 27 runner").
- [x] 3. `AGENTS.md` and `CONTRIBUTING.md` lines, matching the jobs that ship.
- [ ] 4. Push the branch, open a draft PR, and get every job green.

### Verification
- All CI jobs green on the draft PR; a deliberately failing test on a throwaway commit turns the PR red (then dropped).
- The `AGENTS.md` line lists exactly the jobs in `checks.yml`.

## Phase B — packages: fake band out of Release, crash points
Size: ~26 files (+7 fixture renames). 6 steps.

### Files
- `ios/Packages/VeselWearable/Package.swift`: target + product `VeselWearableTesting` (deps: VeselWearable, VeselCore, VeselStorage; resources `Resources/Fixtures`; `.define("VESEL_FAKE_BAND", .when(configuration: .debug))`); `VeselWearable` loses its resources; `VeselWearableTests` depends on it.
- `ios/Packages/VeselWearable/Sources/VeselWearable/{FakeWearableSource,FakeScenario}.swift` → `Sources/VeselWearableTesting/` (git mv); each file wrapped in `#if VESEL_FAKE_BAND`; shaping helpers throw; `fixtureZone` comment.
- `ios/Packages/VeselWearable/Sources/VeselWearable/Resources/Fixtures/**` → `Sources/VeselWearableTesting/Resources/Fixtures/**` (git mv).
- `ios/Packages/VeselWearable/Tests/VeselWearableTests/{BandSyncTests,BandSyncStreamTests,ClockChangeTests,FakeWearableSourceTests,EndNightTests}.swift`: `import VeselWearableTesting`.
- `ios/Packages/VeselWearable/Sources/VeselWearable/Polar/PolarMapping.swift`: comment at `:270`.
- `ios/Tools/make-fixtures.swift`: default output path.
- `ios/project.yml`: `Vesel` and the test target depend on `VeselWearable/VeselWearableTesting`; Release-only `postBuildScripts` "Leave the fake band out of Release"; `ENABLE_USER_SCRIPT_SANDBOXING: NO` on `Vesel`.
- `ios/Vesel/AppEnvironment.swift`: `#if DEBUG import VeselWearableTesting`; fake band under `#if DEBUG && targetEnvironment(simulator)` (and `ShiftedClock`).
- `ios/VeselWidgetsTests/SyncPipelineTests.swift`: import.
- `ios/Packages/VeselStorage/Sources/VeselStorage/AppDatabase.swift`: `appGroup` optional; `StorageError.noAppGroup`, `.notOpened`, `.badDay`; no `as!`, `!.get()`, `preconditionFailure`.
- `ios/Packages/VeselStorage/Sources/VeselStorage/WidgetSnapshot.swift`: same for `appGroup` and `result`.
- `ios/Packages/VeselStorage/Sources/VeselStorage/Records/{SleepNightRecord,NightlyRechargeRecord,BandDataRecords}.swift`: `DayKey(stored:)`; `model` throws; callers `try`.
- `ios/Packages/VeselStorage/Sources/VeselStorage/DayKey+Stored.swift` (new): `DayKey(stored:) throws`.
- `ios/Packages/VeselCore/Sources/VeselCore/DayKey.swift`, `Analysis/UsualBedtime.swift`: `calendar.component`.
- `ios/Packages/VeselSync/Sources/VeselSync/PinnedSession.swift`: guard the cast.
- `ios/Packages/VeselStorage/Tests/VeselStorageTests/StoredDayTests.swift` (new): a stored row with a bad day throws `badDay`, not a crash.
- `ios/Packages/VeselSync/Tests/VeselSyncTests/…`: only if an existing test fake returns a non-HTTP response (keep it out otherwise).
- `.github/workflows/checks.yml`: ios job adds `xcodebuild build -scheme Vesel -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`.
- `.agents/skills/testing/SKILL.md`: fixtures path / `VeselWearableTesting` (now true).

### Steps
- [x] 1. Split the package: new target, git mv sources and fixtures, update test imports and `make-fixtures.swift`. `swift ios/Tools/make-fixtures.swift` reproduces the same files (no diff).
- [x] 2. Wire the app: `project.yml` deps, `#if DEBUG` imports, the Release post-build guard.
- [x] 3. Confirm `swift build -c release` of the package (or a Release Xcode build) compiles `VeselWearableTesting` to an empty module. Build Release for a device unsigned; confirm the guard passes and the `.app` has no `Fixtures` and no `VeselWearable_VeselWearableTesting.bundle`. Then delete the bundle line from the script once and confirm the guard fails (proves it bites); restore it.
- [x] 4. Storage crash points + `DayKey(stored:)` + test.
- [x] 5. Core (`DayKey`, `UsualBedtime`), Sync (`PinnedSession`), fake band `try!`.
- [x] 6. CI Release step; run the full checks.

### Verification
- Full contract checks pass; CI green.
- `grep -rn "as! \|!\.get()\|try! \|preconditionFailure" ios/Packages/*/Sources` → only the commented `PolarMapping.swift:270` and `PolarWearableSource.swift:191` (a real invariant; comment it).
- Release device build: no fixtures, no fake band string, guard green.
- Simulator: the contract's `run` with `-VeselScenario normal -VeselNow 2026-10-25T15:00:00Z` shows Today with data; `-VeselScenario pairing` shows pairing.

## Phase C1 — app start: recovery screen, AppEnvironment split, test target rename
Size: ~20 files. 6 steps.

### Files
- `ios/Vesel/AppEnvironment.swift`: designated init + `live()`; routing, Shortcut, LaunchOptions, Simulator set-up moved out; `didFinishLaunching` no longer registers BGTasks.
- `ios/Vesel/AppRouter.swift` (new), `ios/Vesel/Intents/ShortcutSync.swift` (new), `ios/Vesel/LaunchOptions.swift` (new), `ios/Vesel/SimulatorSetup.swift` (new).
- `ios/Vesel/AppStartup.swift` (new): environment or problem, `retry()`.
- `ios/Vesel/StorageProblemView.swift` (new): the recovery screen.
- `ios/Vesel/AppDelegate.swift`: builds `AppStartup`; no `fatalError`; BGTask registration through the startup; notification tap → router.
- `ios/Vesel/VeselApp.swift`: `RootView` or `StorageProblemView`; scene-phase work only with an environment; `.onOpenURL` → router.
- `ios/Vesel/RootView.swift`: takes `AppRouter`; tab requests from it.
- `ios/Vesel/Background/BackgroundScheduler.swift`: `register(_ startup: AppStartup)`; no environment → `complete(success: false)`; comment both `assumeIsolated`.
- `ios/Vesel/Background/SyncPipeline.swift`, `ios/Vesel/Background/ContinuedRead.swift`: comment the `assumeIsolated` (handlers registered `using: .main` run on the main queue; the compiler can't see it).
- `ios/Vesel/Background/BandWakeHandler.swift`: takes what it uses, if it reached into routing.
- `ios/Vesel/Intents/SyncVeselIntent.swift`: `@Dependency var startup: AppStartup`; no environment → "Open Vesel first."
- `ios/project.yml`: `VeselWidgetsTests` → `VeselAppTests` (target, path, bundle id `…ios.app.tests`, scheme).
- `ios/VeselWidgetsTests/` → `ios/VeselAppTests/` (git mv, 4 files).
- `ios/VeselAppTests/AppRouterTests.swift` (new): each `vesel://` link → tab and page; unknown host → nothing.
- `ios/VeselAppTests/StorageProblemTests.swift` (new): error → problem kind; `retry()` after a fixed cause gives an environment (injected opener closure); a protected-data notification (posted to an injected `NotificationCenter`) retries; launch work runs exactly once on success, also when the app is in the background.
- `docs/how-it-works/storage-problems.md`: status line notes the launch half is built.
- `docs/design/screens.md`: the recovery screen and its three states.
- `CHANGELOG.md`: "If Vesel can't open its data, it now says so and lets you try again, instead of closing."

### Steps
- [x] 1. Rename the test target; checks green before anything else moves.
- [x] 2. Move `LaunchOptions`, `SimulatorSetup`, `ShortcutSync`, `AppRouter` out; `AppEnvironment` gets `init(database:band:clock:launch:defaults:)` and `live()`.
- [x] 3. `AppStartup` with an injectable opener (`() throws -> AppEnvironment`, default `AppEnvironment.live`) and `NotificationCenter`; retries on protected data available and scene active; launch work once on success. `AppDelegate`, `VeselApp`, `SyncVeselIntent`, `BackgroundScheduler`.
- [x] 4. `StorageProblemView` (load `writing` and `accessibility`): Dynamic Type, VoiceOver reads title then message, 44 pt button.
- [x] 5. `assumeIsolated` comments.
- [x] 6. Tests, docs, full checks; Simulator shots of the recovery screen (a Debug launch argument `-VeselStorageProblem olderApp|setUp|couldNotOpen` makes the opener throw; it sits with the other launch options under `#if DEBUG`).

### Verification
- Full checks; CI green.
- `grep -rn "fatalError" ios/Vesel` → none.
- Simulator: each `-VeselStorageProblem` value shows its screen; "Try again" with the argument still set stays there; normal launch unchanged.
- Simulator: tapping a widget link and a notification still opens Today / the page (`xcrun simctl openurl booted vesel://sleep`).
- **Owner only:** on the iPhone, a normal launch and a background sync still work (nothing should look different).

## Phase C2 — narrow model seams
Size: ~38 files, mechanical. 5 steps.

### Files
- Models, each `init` takes only what it uses: `ios/Vesel/Today/TodayModel.swift` (+ `defaults`), `Journal/JournalModel.swift`, `Body/BodyModel.swift`, `Body/AboutYouModel.swift`, `Pairing/PairingModel.swift` (`bandSync`, `database`, `clock`, `units`, `launchStep`, `didPair`), `Loop/LoopSettingsModel.swift`, `Recovery/RecoveryModel.swift`, `Sleep/SleepModel.swift`, `Stress/StressModel.swift`, `Steps/StepsDayModel.swift`, `Pages/ReadingDay.swift` (`ReadingDayModel`; the launch scrub becomes a `takeScrub` closure), `Pages/SignalPage.swift` (`SignalPageModel`), `Pages/HeartRateDays.swift` (`HeartRateDaysModel` + latest reading), `Days/WeekStrip.swift`, `Days/DayCalendar.swift`.
- `ios/Vesel/RootModel.swift` (new): first day → `DaySelection`, band battery.
- Views that build their models from the environment's parts (they keep `let environment`): `RootView.swift`, `Today/TodayView.swift`, `Journal/JournalView.swift`, `Body/BodyView.swift`, `Loop/LoopSettingsView.swift`, `Loop/SyncingView.swift`, `Loop/BandDataReportView.swift`, `Pages/{CalmPage,HeartRatePage,NightlyDayPart,OverTimePart,PageRoute,RecoveryPage,SleepPage,StepsPage}.swift`, `Pairing/PairingFlow.swift`.
- `ios/Vesel/Background/SyncPipeline.swift`: `bandDataReport(from:through:)`, `isStreaming` (Debug report only).
- `.agents/skills/layers/SKILL.md`: the end-state lines from Rule gaps, now true.

### Steps
- [x] 1. Add `RootModel` (first day, battery; restarted on scene active) and move both observations out of `RootView`.
- [x] 2. Day-independent models: Today, Journal, Body, AboutYou, Pairing, LoopSettings, and their views.
- [x] 3. Page models: Recovery, Sleep, Stress, StepsDay, ReadingDay, SignalPage, HeartRateDays (+ latest reading out of `HeartRatePage`), WeekStrip, DayCalendar.
- [x] 4. `BandDataReportView` through `SyncPipeline`.
- [x] 5. No model file mentions `AppEnvironment`. Full checks; Simulator walk.

### Verification
- Full checks; CI green.
- `grep -n "AppEnvironment" ios/Vesel/*/*Model*.swift ios/Vesel/RootModel.swift` → none.
- `grep -rn "\.database\.observe" ios/Vesel --include=*View.swift ios/Vesel/RootView.swift ios/Vesel/Pages/HeartRatePage.swift` → none.
- Simulator walk (`normal`, `-VeselNow 2026-10-25T15:00:00Z`): Today, Journal (calendar, week strip, a past day), Body, each signal page D/W/M/3M, Loop & settings, Syncing, band data report (`-VeselScreen report`), pairing (`-VeselScenario pairing`). Screenshots match `main`.

## Phase C3 — calm read problems, model tests
Size: ~24 files. 5 steps.

### Files
- `ios/Packages/VeselStorage/Sources/VeselStorage/AppDatabase.swift`: `public static func isPaused(_ error: any Error) -> Bool` (`SQLITE_INTERRUPT`, or `SQLITE_ABORT` with GRDB's suspension message).
- `ios/Packages/VeselStorage/Tests/VeselStorageTests/PausedTests.swift` (new): on a temp-dir database opened with the app's configuration (`observesSuspensionNotifications`), suspend, then a direct read and a write fail with errors `isPaused` accepts; a plain `SQLITE_ABORT` without the suspension message and a constraint error are not accepted.
- `ios/Vesel/ReadProblem.swift` (new): the shared catch helper (`CancellationError` and `isPaused` → ignore, else set the flag) and `ObserveKey.attempt`.
- `ios/Vesel/Theme/ReadProblemCard.swift` (new): plain values; `ErrorCard` with the fixed words.
- The 13 `catch {}` files: `Today/TodayModel.swift`, `Journal/JournalModel.swift`, `Body/BodyModel.swift`, `Recovery/RecoveryModel.swift`, `Sleep/SleepModel.swift`, `Stress/StressModel.swift`, `Steps/StepsDayModel.swift`, `Days/DayCalendar.swift`, `Days/WeekStrip.swift`, `Loop/SyncingView.swift`, `Pages/HeartRateDays.swift`, `RootModel.swift`, `Units/UnitsStore.swift` (last two: no card; restarted on activation).
- `ios/Vesel/AppEnvironment.swift`: `foreground()` restarts the units task when it has ended.
- Views that show the card: `Today/TodayView.swift`, `Journal/JournalView.swift`, `Body/BodyView.swift`, `Pages/SignalPage.swift` (one card for the page part), `Loop/SyncingView.swift`.
- `try?` audit: `Body/AboutYouModel.swift`, `Loop/LoopSettingsModel.swift`, `Pairing/PairingModel.swift` where a save's failure is hidden.
- Tests (new, `ios/VeselAppTests/`): `TodayModelTests` (snapshot for today only; alerts not shown before they fire; read problem then Try again), `JournalModelTests` (follows the picked day), `BodyModelTests` (period window, units), `PairingModelTests` (fake band pairing scenario: pair → profile saved → `didPair` called; band refuses → error, nothing saved), `LoopSettingsModelTests` (alert switch saved; forget calls `didForget`), `ReadProblemTests` (paused → no card; other error → card; restart clears).
- `docs/design/screens.md`: the read-problem state, once, for every screen.
- `docs/how-it-works/storage-problems.md`: Planned → Built.
- `.agents/skills/testing/SKILL.md`, `.agents/skills/layers/SKILL.md`: the end-state lines from Rule gaps.
- `CHANGELOG.md`: "When Vesel can't read something, it says so and offers Try again, instead of loading forever."

### Steps
- [x] 1. `isPaused` + its test.
- [x] 2. `ReadProblem` helper, `ObserveKey.attempt`, `ReadProblemCard` (`writing`, `accessibility`).
- [x] 3. Replace the 24 `catch {}`; wire the card into the five views.
- [x] 4. `try?` audit; list kept vs changed in the PR.
- [x] 5. Model tests; full checks; Simulator: background the app for a minute and come back on every tab: no card appears (paused database is not a problem).

### Verification
- `grep -rn "catch {}" ios/Vesel` → none.
- Full checks; CI green; the six new test files run in `VeselAppTests`.
- Simulator: a Debug launch argument `-VeselReadProblem` makes the first observation on Today throw once; the card shows; Try again loads Today.
- Simulator: background ↔ foreground 5× on Today, Journal, a page: never a card.

## Phase D — previews
Size: ~32 files, additive. 4 steps.

### Files
- `ios/Vesel/Preview/PreviewEnvironment.swift` (new, `#if DEBUG`): one shared in-memory database per scenario, filled once straight from the fake band into storage; environment + `PreviewHost(scenario:)`.
- Screen previews (`#if DEBUG`): `Today/TodayView.swift` (normal, first day, read problem), `Journal/JournalView.swift`, `Body/BodyView.swift`, `Body/FitnessView.swift`, `Pages/{RecoveryPage,SleepPage,CalmPage,HeartRatePage,StepsPage}.swift`, `Sleep/NightView.swift`, `Recovery/RecoveryView.swift`, `Loop/{LoopSettingsView,SyncingView,WhatThingsMeanView,ForgetLoopSheet}.swift`, `Meaning/MeaningSheet.swift`, `Pairing/{BeforeYouStartView,LookingForBandView,AboutYouView}.swift`, `StorageProblemView.swift` (three kinds), `Today/{GoodMorningCard,AlertCard}.swift`.
- Widget previews: `ios/VeselWidgets/{TodayWidget,RecoveryRingWidget,SleepLockWidget,StressNowWidget}.swift` from `WidgetSamples`.
- Theme previews (plain values): `ios/Vesel/Theme/{ErrorCard,EmptyState,Skeleton,RangeLine,ReadingLineChart,ReadProblemCard}.swift`.
- `.agents/skills/layers/SKILL.md`: the previews line from Rule gaps.

### Steps
- [x] 1. `PreviewEnvironment` and `PreviewHost`; prove with Today.
- [x] 2. Screens, then pairing and sheets.
- [x] 3. Widgets and Theme.
- [x] 4. Release device build still passes the fake-band guard; full checks. (Fast checks and the compiles; the full checks are left to the final verify.)

### Verification
- Every listed preview renders in Xcode's canvas (or, headless, `xcodebuild build` for Debug Simulator compiles them; a coder spot-checks 3 in Xcode).
- Release device build: guard green (previews add no Release reference to the fake band).
- Full checks; CI green.

## Phase E — swift-format
Size: config + 1 mechanical commit (most Swift files) + 3 files. 3 steps.

### Files
- `.swift-format` (new).
- All Swift under `ios/` and `mac/`: format only, its own commit.
- `.github/workflows/checks.yml`: the `packages` job (macOS) adds `git ls-files -z '*.swift' | xargs -0 xcrun swift-format lint --strict`.
- `AGENTS.md` `## Factory` `checks`: prepend the same format lint (from git's file list) to fast and full.
- `CONTRIBUTING.md`: how to format before a PR.

### Steps
- [x] 1. Write the config; run `lint` and tune only rules that fight the house style (keep the list short; record each in the PR).
- [x] 2. `format -i` over `git ls-files '*.swift'`; commit alone ("Format with swift-format"); full checks must pass with no other change. (Fast checks and the compiles passed; the full checks are left to the final verify.)
- [x] 3. CI step, contract, CONTRIBUTING.

### Verification
- `git ls-files -z '*.swift' | xargs -0 xcrun swift-format lint --strict` exits 0; full checks; CI green.
- The format commit changes only whitespace, line wrapping, import order and trailing commas: a reviewer skims `git diff -w` on it and any other change is a finding.

## Decisions
1. Licence: Apache 2.0; CLA still transfers rights to the UG so it can pass them on. **mine** (2026-10-31)
2. Phase order and split: A1, A2, B, C1, C2, C3, D, E; one PR each. **agent's**
3. calmer-morning phase 1 merges before B; its phases 2–3 after C2. **mine** (2026-10-31)
4. Fake band: `VeselWearableTesting` product compiled only in Debug (`VESEL_FAKE_BAND`); Release strips its bundle with a build-phase guard. **agent's**
5. Seams: concrete parts per model (database, clock, stores, closures), no protocols, no DI framework; views keep getting `AppEnvironment` from their parent and build models in `init`. **agent's**
6. Database won't open → recovery screen, never a delete or reset; background work skips quietly; retries by itself at first unlock and on coming to the front. **agent's** (touches a risk area: shown to the owner)
7. Recovery screen words (writing skill may polish, meaning stays):
   - Older app: "Vesel needs an update" / "Your data on this phone was saved by a newer version of Vesel. Install the newer version to open it. Nothing has been deleted."
   - Couldn't open: "Vesel can't open your data right now" / "Your data is still on this phone. Unlock your iPhone, then try again." / "Try again"
   - Set-up: "Vesel isn't set up right" / "This build is missing its shared data folder. Rebuild it with your own bundle prefix (see the README)." **mine** (approved 2026-10-31)
8. Read problem: one card per screen, "Couldn't show this" / "Vesel couldn't read this just now. Your data is still on this phone." / "Try again". A paused database never shows it. **mine** (approved 2026-10-31)
9. No per-file Apache headers; `NOTICE` + `LICENSE` only. **agent's**
10. CI: GitHub-hosted macOS runners, newest Xcode (27 when present), Simulator `OS=latest`; actions pinned by SHA; no secrets; `AGENTS.md` says exactly what it runs. **agent's**
11. swift-format last, line length 160, `NeverForceUnwrap`/`NeverUseForceTry` off, files from `git ls-files`. **agent's**
12. Test target name `VeselAppTests`. **agent's**
13. Lock-screen widgets get `.privacySensitive()` (Phase C3), and the server logs the request path with `repr()` (Phase A2). **mine** (2026-10-31)
14. Keep the git history when going public: scanned clean (gitleaks, deleted files, messages, authors). **agent's**

## Verification
Per phase above. Across all phases: the contract's full `checks` (in `AGENTS.md`) and CI green on each PR; the contract's `run` on the Simulator with `-VeselScenario normal -VeselNow 2026-10-25T15:00:00Z`. Harness: none. **Owner only:** iPhone launch, background sync and widgets after C1 and C2; lawyer review of the CLA.

## Deviations
- A2: GitHub has no `macos-27` label. Its `xcode-27` image (public preview, macOS 27) carries Xcode 27.0–27.2; `macos-26` stops at Xcode 26.6. So `packages`, `backup-kit`, `ios` and `mac` run on `xcode-27` with Xcode 27.2, the Xcode the local checks use, and nothing is left out. `server` stays on `macos-26`. A preview image has no SLA and may queue.
- A2: CI's Simulator is `name=iPhone 17` with no OS: the `xcode-27` image has no iPhone 17 Pro Max, and `OS=latest` would ask for iOS 27.2, which has no runtime on the image.
- A2 (decision 13): the new log test sends `\x1b` and `\x0b` in the path, not a newline. Starlette already drops tab, CR and newline from `request.url.path`; other control characters reach the log, and `repr()` escapes them.
- A2 step 4 (push, draft PR, CI green) is left to whoever pushes: this run doesn't push.
- B: the guard script declares the copied `VeselWearable_VeselWearableTesting.bundle` as an input file. Without it, Xcode copied the package's resource bundle after the script on some builds, so the bundle shipped and the guard passed. With it, two fresh Release builds came out clean, and with the removal line taken out the guard failed the build.
- B: `VeselWearableTesting` depends on VeselWearable and VeselCore only; it uses nothing from VeselStorage.
- B: the widget's `readSnapshot` returns `.empty` when the App Group is missing, as it already did for a missing container; only the app's `shared()` throws `noAppGroup`.
- B step 6: the full checks are left to the final verify (this lane runs the fast checks and the compiles only).
- C1: `AppRouter` is built by `AppEnvironment` (`environment.router`), so a notification or widget tap with no environment does nothing. `VeselApp` hands it to `RootView(environment:router:)`.
- C1: `AppStartup` takes a `launch` closure (default `didFinishLaunching()`) beside the opener, so tests count the launch work without starting the band. A BGTask, the Shortcut and Try again each call `retry()` first.
- C1: Try again shows only on "can't open right now"; an older app or a wrong build can't be fixed by trying again (`docs/design/screens.md`).
- C1: `-VeselStorageProblem` maps to `StorageError.newerSchema`, `.noAppGroup` and `.notOpened`, read in `AppEnvironment.live()` under `#if DEBUG`.
- C1: `BandWakeHandler` is unchanged: it never reached into routing.
- C1 step 6: the full checks, the Simulator shots of the recovery screen and the widget-link check are left to the final verify (no Simulator in this lane).
- C2: the latest stored heart rate moved into `ReadingDayModel` (`observeLatest`), not `HeartRateDaysModel`: the heart rate page's D part is built on `ReadingDayModel`; `HeartRateDaysModel` serves only W, M and 3M.
- C2: `TodayModel` takes the live reading as a closure (`liveReading`), so its tests need no band. `LoopSettingsModel` takes `BandSync` and `SyncPipeline` (connection, factory reset, idle, backup) and a `runSync` closure for the continued read, like `SyncingModel`.
- C2: the band data report reads the connection log once from the database in the view; it isn't an observation and doesn't reach the band.
- C2: `AppEnvironment` keeps `defaults`, so Today's "Still in bed" day uses the same store as `SyncStatusStore` (`.standard` in the app, a throwaway suite in tests).
- C2 step 5: the full checks and the Simulator walk are left to the final verify (this lane runs the fast checks and the compile).
- C3: GRDB lets reads through a paused WAL database; only writes and statements already running fail. `PausedTests` pauses one temp-dir pool (GRDB's per-database `suspend()` via `@testable import GRDB`, because the app's `suspend()` notification would pause every database in the parallel test run) and checks a write's real error; `SQLITE_INTERRUPT` is built by hand.
- C3: `ReadProblem` is a small `@Observable` class each model owns (`reads.observe { … }` clears the flag when it starts, sets it on a real failure); `readProblem` on the model reads it. Today and Journal also count their `ReadingDayModel`.
- C3: page parts don't show their own card: they hand `readProblem` to the period page (`\.showReadProblem`), which shows one card in the part's place; Try again builds the part afresh. So `SignalPage.swift` and each part view change, not only the five listed views.
- C3: the week strip and the calendar keep their last dots on a failed read, like the helpers: their dots are extras and picking a day still works. Syncing now reads only while Vesel is in front (`ObserveKey`), so a paused database can't end its read for good.
- C3: the fallbacks that drew an empty chart after any failed read (`ReadingDayModel`, `HeartRateDaysModel`, `BodyModel`) are gone: a real failure shows the card; a paused or cancelled read waits for the restart.
- C3: `-VeselReadProblem` is a `LaunchOptions` field (`failsFirstRead`) that `TodayModel` takes in `init`, so `TodayModelTests` and phase D's preview use the same seam.
- C3: `ReadProblemTests` covers cancel, failure and restart; the paused case lives in `PausedTests` (the app test bundle can't link GRDB, which the app links statically).
- C3 `try?` audit: changed `LoopSettingsModel.setAlert` (a switch that couldn't be saved flips back). Kept: About you's units switch (the picker shows the stored value, so a failed save shows), its profile save (already shows "not saved"), Loop & settings' one-off reads and backup counts (shown as "Not read yet"), `forgetBand` after a reset (handling it needs a new step on the Forget sheet; a risk area, left for its own change), Pairing's read of a stored waist (best effort), and the rest outside these three files (sleeps, notification asks, Simulator set-up, widget reloads, pipeline best-effort reads), unchanged.
- C3 (decision 13): both lock screen widgets get `.privacySensitive()`.
- C3 step 5: the full checks and the Simulator background/foreground walk are left to the final verify; the six new app test classes ran once on a fresh Simulator (14 tests, green).
- D: previews are 53 in 32 files. Pages preview through `SignalPage` (`PreviewPage`), not through each part view (`RecoveryDay`, `SleepDay` and the rest need a page around them for the period switch and the page environment). `RecoveryView` and `NightView` get a small `#if DEBUG` wrapper that builds their model, since they take a model or a `NightReport` (which has no public initialiser).
- D: `PreviewEnvironment` has four scenarios (`normal`, `firstDay`, `unpaired`, `readProblem`); `readProblem` is `normal` data with `LaunchOptions.failsFirstRead`. `firstDay` uses its own clock (29 Sep 2026, where its data ends). The fill stores one sync run and runs `MetricsUpdater.updateAfterSync()` (what `SyncPipeline` runs after a read); nothing else of the pipeline.
- D: `PreviewHost` shows "The preview data didn't load." if the fake band's fixtures or the fill fail, instead of a spinner forever. The pairing views preview on a model that isn't searching (`PreviewPairing`): the fake band pairs at once, so a live search would jump to step 3.
- D: widget previews use `#Preview(as:)` with `VeselEntry.previewStates()` (normal, low, learning, no data, old) added to `WidgetSamples.swift`. The previews compile in Debug (`xcodebuild build-for-testing`) and the Release build has none; they were not opened in Xcode's canvas, and the fill ran only as compiled code, not in a canvas or test (the Simulator is off limits in this lane).
- E: the config adds `indentConditionalCompilationBlocks: false` (the code keeps `#if` bodies flush left), beside the plan's `lineLength` 160, `respectsExistingLineBreaks`, `lineBreakBeforeEachArgument: false` and the two `Never…` rules off. No rule was turned off globally; `AlwaysUseLowerCamelCase` raised nothing.
- E: the format touched 138 Swift files (`git diff -w` 131: the rest changed indentation only). It also wraps long string literals and comments onto a continuation line, so `lint --strict` exits 0 with the 160 limit and no manual edits. Three commits: config, format (alone), CI + contract + CONTRIBUTING.
- E: `swift-format` is 6.4.4 (Xcode 27.2), the same Xcode the `xcode-27` CI image carries.

## Rule gaps
Applied now (already true):
- testing: app screen-model tests build the model from `AppDatabase.inMemory()`, a `FixedClock` and plain closures, like `SyncingModelTests` (added to `.agents/skills/testing/SKILL.md`).

End state, applied by the phase that makes it true:
- testing (B): the fake band and its fixtures live in `VeselWearableTesting`, compiled only under `VESEL_FAKE_BAND` (Debug); app code imports it only under `#if DEBUG`; the Release guard in `ios/project.yml` must stay.
- layers (C1): `AppEnvironment` wires; `AppRouter` routes; `AppStartup` decides between the app and the recovery screen and retries at first unlock and on activation; BGTask handlers register before launch ends even without an environment.
- layers (C2): screen models take only the parts they use, never `AppEnvironment`; views get `AppEnvironment` from their parent and build models in `init`; no view observes the database.
- layers (C3): every screen observation `catch` goes through `ReadProblem`; one `ReadProblemCard` per screen; a paused database is never a problem.
- layers (D): every screen and widget has a `#Preview` under `#if DEBUG` from `PreviewEnvironment` (shared database, no pipeline); Theme previews use plain values.
- AGENTS.md (A2, E): CI and the format lint in `checks`.
