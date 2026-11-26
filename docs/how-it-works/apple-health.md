# Apple Health

**Status:** Built for heart rate, resting heart rate, respiratory rate, sleep and steps. HRV, energy and workouts are planned (Phase 2 of `docs/plans/2026-11-26-apple-health.md`); until then heart rate stays on its day. Decision `docs/decisions/2026-11-26-apple-health.md`.

> Vesel copies your Loop's readings into Apple Health, so other apps you allow there can read them. It never reads from Health.

## Intent
The owner's other app, Mira, reads Apple Health. Vesel stays the source of truth: Health gets a copy, written one way.

## How it works
- **Turning it on:** Loop & settings › Apple Health › "Write to Apple Health" (off until turned on). Turning it on shows Apple's own Health sheet and writes everything Vesel has (again, if it was on before: nothing doubles, and anything deleted in Health comes back). After an update that writes new kinds, the sheet shows once more on opening Vesel, with only the new ones. Nothing asks at any other time. What you don't allow is skipped and written later if you allow it in Health › your profile › Apps › Vesel.
- **When it writes:** after every read of the Loop (also in the background), and when Vesel comes to the front, never while a read runs. The first time, it writes all the history Vesel has, newest first.
- **Locked phone:** Apple Health can't be fully used while the iPhone is locked, and most reads happen then, so Vesel doesn't write while locked. Nothing is lost: what isn't written yet waits on the phone and is written the next time Vesel runs with the phone unlocked (at the latest when you open Vesel).
- **Corrections:** each thing Vesel writes carries its own id (Apple's sync identifier) and a version (the time it was written). When a reading changes (a later read of the Loop, your fix to a workout), Vesel writes the new copy, which replaces the old one in Health, then removes anything of its own it wrote for that day, night or workout before. When a reading goes away (a number Polar withdrew, a workout marked "Not a workout"), its copy is removed. Nothing is ever written twice. Vesel never touches what other apps wrote.
- **Turning it off:** Vesel stops writing. What's in Health stays; to remove it: Health › your profile › Apps › Vesel › Delete All Data.
- **The device:** every sample says it came from a Polar Loop.
- **Two sources:** the iPhone counts steps and works out active and resting energy too. Put the Loop first in Health's Data Sources & Access for Steps, Active Energy and Resting Energy, so Health doesn't add them up twice (you do this once in Health).

## What is written, and where each number comes from

| In Health | From | How |
|---|---|---|
| Heart rate | every stored 24/7 reading (`hr_sample`) | one sample per reading, at its time, in bpm. Readings inside a workout are written with that workout instead (below), when workouts are allowed. |
| Resting heart rate | the number Vesel shows as Resting HR | one per night over the sleep window (no sleep: that day, midnight to midnight): 60 000 ÷ the mean beat interval Polar measured overnight (Nightly Recharge). |
| Respiratory rate | the number Vesel shows as Breathing | one per night over the sleep window: 60 000 ÷ the mean breath interval Polar measured overnight (in ms), in breaths per minute. |
| Sleep | Polar's sleep result (`sleep_night`) | "In bed" from sleep start to end; each stage as its own piece: Polar's Light → Core, Deep → Deep, REM → REM, Wake → Awake. Stretches Polar marked unknown are left out. Not rescored. |
| Steps | the Loop's per-minute steps (`activitySamples`) | one sample per clock hour with steps, start to end of that hour (the current hour ends at its last read minute). Today's hours are rewritten as more of the day is read. |
| Resting energy | the day's resting calories (BMR) from Polar's daily summary | one sample per day, from midnight to the end of the day (today: to the last read). |
| Active energy | the day's activity calories from Polar's daily summary | one sample per day as above, less what the day's workouts carry (below) when workouts are allowed, so Health doesn't count a workout twice. Never under 0. |
| HRV (SDNN) | the Loop's beat-to-beat readings (`ppi_sample`) | one per night over the sleep window. Each beat-to-beat recording (about 1½ minutes) that lies entirely inside the sleep window is cleaned like stress (beats the Loop flagged, beats outside 300–2000 ms, jumps over 20 % dropped); a recording counts with at least 60 clean beats and 80 % of its beats kept. Its SDNN is the standard deviation of its clean beat intervals. The night's HRV is the median over the recordings that count, at least 5 of them. Stored as a worked-out number (`heart.sdnn`, method `sdnn` v1) with its inputs; recomputed when late beats for that night arrive. Never Polar's RMSSD. |
| Workouts | the Loop's workouts (`workout`), your fixes (`workout_choice`), the phone's route (`workout_route`) | Sport from the Loop or from your fix: Running, Cycling, Swimming, Strength (traditional strength training); a sport Vesel only guessed, or none, is Other (guesses change with later workouts). Start and end from the Loop; a workout past midnight counts on its start day. Active energy: Polar's workout calories less the resting calories of its length (the day's BMR × its length ÷ 24 h); no calories, no energy. Heart rate: the Loop's own workout readings (each non-zero reading at its time); with none, the 24/7 readings inside it. Route: the route Vesel shows, cut to the workout (points less exact than 25 m left out), if routes are allowed. A workout you marked "Not a workout" is not written, and is removed if it was. |

Not written: skin temperature (Apple's wrist temperature type is for Apple Watch only, and body temperature would be the wrong label), stress, recovery, Polar's HRV (RMSSD), cardio load.

## Storage
- One bookkeeping table, `health_write`: for each day, night or workout, when it was last written, the version, and a fingerprint of what was written. Not health data; not sent to the Mac backup. Turning the switch on clears it. What's pending is worked out from it and the time each reading was stored (`band_ledger.stored_at`, `computed_metric.computed_at`, a workout's stored, choice and route times).
- The switch is the setting `health.write`; how the last write went (time, outcome, days left, kinds not allowed) is `health.lastRun`.

## Never
- Never read from Apple Health.
- Never write a number Vesel can't explain, or under a label that isn't true.
- Never nag about Health: no alert, no badge, nothing on Today.
