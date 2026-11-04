---
name: testing
description: Use when a change adds or changes analysis, storage, sync or a test.
---

# Testing

What we test: health formulas with written-out expected numbers, migrations, the upload contract, deleting from the band, and the invariants in `AGENTS.md`. Prefer one test that runs a real path (band data in → stored → worked-out numbers, sync log or upload out) over several small ones on the same ground. Don't test Swift, GRDB or SwiftUI themselves, restate constants (unless they are stored values older versions wrote), or test the fake band beyond what the Simulator scenarios need.

- Logic goes in a Swift package and its tests run with `swift test` on the Mac. Only code that needs iOS (the Polar SDK, the app, widgets) is tested in the Simulator.
- Analysis (baselines, HRV, stress, alerts) gets Swift Testing tests on recorded sample data, with the expected numbers written out.
- Storage tests run against an in-memory GRDB database.
- Code that needs the band uses a fake `WearableSource`; tests never need a real Loop.
- Workout mapping tests build the SDK's protobuf structs, never a real session file.
- App screen-model tests build the model from `AppDatabase.inMemory()`, a `FixedClock` and plain closures for app actions, like `SyncingModelTests`.
- Whether an error is a paused database is tested on GRDB's own errors in VeselStorage (`PausedTests`); the app tests can't link GRDB.
- Server code gets pytest tests.
- Time comes from an injected clock, never `Date()` directly in logic. Waits and time limits on the band (`ReadLimits`) are injected so tests make them short.
- App tests build `SyncStatusStore(defaults:)` on a throwaway suite, never `.standard`.
- Fixtures in the repo are synthetic. Real band recordings never go into git (the repo lives on GitHub); keep them in gitignored local folders.
- The fake band's fixtures come from `ios/Tools/make-fixtures.swift` (deterministic); regenerate with `swift ios/Tools/make-fixtures.swift`, never hand-edit them. The Simulator picks a scenario with `-VeselScenario <name>`.
- The fake band and its fixtures live in `VeselWearableTesting`, compiled only under `VESEL_FAKE_BAND` (Debug). App code imports it only under `#if DEBUG`. The Release guard in `ios/project.yml` ("Leave the fake band out of Release") must stay.
- Changing how an analysis works bumps its method version (stored in `computed_metric`); the next read recomputes every night stored under the old version.
- A stress level worked out outside `StressUpdater` uses that day's stored baseline and floor, never a new baseline, and re-reads when the stored `stress.readings` rows change.
- Stress tests always include a flagged-sample (blocker or no skin contact) case, a high-activity case and a reading inside a workout.
