# Vesel writes its readings to Apple Health, one way

**Date:** 2026-11-26
**Who decided:** mine; the items marked agent's below were decided while planning
**Plan:** docs/plans/2026-11-26-apple-health.md
**Supersedes:** `2026-10-26-no-cloud.md`, in part (the "no Apple Health or iCloud" words)

## Context

The owner's other app, Mira (self-hosted on the owner's own server), already reads Apple Health. To use the Loop's readings there, Vesel has to put them into Apple Health on the iPhone. Until now, health data went nowhere but the phone and the owner's Mac.

## Decision

- Vesel writes its readings to Apple Health on the iPhone. It never reads from Apple Health.
- Apple Health on the phone, and Apple's end-to-end encrypted iCloud backup of Health, are allowed places for the data. Nothing else changes: no Polar cloud, no outside analytics.
- Written: heart rate (every reading), resting heart rate (one a night, the number Vesel shows), sleep with its stages, breathing rate (one a night), steps hour by hour, active and resting energy, workouts with sport, time, calories, heart rate and route, and HRV as SDNN that Vesel works out itself from the Loop's beat-to-beat readings.
- Not written: skin temperature (Apple's wrist temperature is for Apple Watch only; body temperature would be the wrong label), stress, recovery. HRV is never Polar's RMSSD under Apple's SDNN label.
- All history Vesel has is written once, then each new reading after it is stored.
- A switch in Loop & settings turns it on (off until then). Apple's own permission sheet appears when the owner turns it on, and once more only if a later Vesel writes new kinds.
- The owner puts the Loop first in Health's Data Sources by hand (Steps; the agent added Active and Resting Energy to the same step), so the iPhone's own numbers don't add up with the Loop's.

### Made while planning (the owner confirms at the plan gate)

- HRV (SDNN) is one number a night: the median of the SDNN of each beat-to-beat recording (about a minute and a half) taken entirely while asleep, clean beats only. Short recordings during still sleep are what Apple's own SDNN readings look like, and the median keeps one restless recording from moving the night.
- A reading Vesel corrects later replaces its copy in Health; one that went away (a workout marked "Not a workout") is removed from Health. Vesel never touches anything in Health it didn't write.
- Turning the switch off stops writing. What's already in Health stays there; the owner can delete it in the Health app. Turning it on again writes everything again (nothing doubles).
- A workout's sport is written only when the Loop or the owner named it; Vesel's guesses are written as Other, because a guess can change with later workouts.

## Why

Mira needs the readings, and Apple Health is the one place on the phone both apps can share without a new server or connection. Apple Health stays on the phone, and its iCloud backup is end-to-end encrypted, so no one else can read it.

## Alternatives

Sending the data from the Mac backup to Mira (a new network path and a new server to secure). Writing to Health without iCloud (Health has no per-app switch for that; the iCloud backup is the owner's own setting). Writing Polar's RMSSD as SDNN (wrong label, numbers not comparable). All rejected.

## What it means

`AGENTS.md` Non-negotiables and `docs/intent.md` now allow Apple Health on the phone and its encrypted iCloud backup, and nothing else beyond the owner's Mac. Every other destination still needs a new decision. To undo it: turn the switch off and delete Vesel's data in Health › your profile › Apps › Vesel.
