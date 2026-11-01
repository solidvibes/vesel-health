# Polar's band numbers as-is, plus our own analysis

**Date:** 2026-10-26
**Who decided:** mine

## Context

Interview, round 2: stress, recovery and exercise. Supersedes the April 2026 vision's "no custom algorithms".

## Decision

Show Polar's on-band results (sleep stages, Nightly Recharge, activity, training sessions) unchanged. Compute stress, baselines and alerts ourselves from raw 24/7 heart rate and beat-to-beat (PPI) data.

## Why

Polar's Nightly Recharge comes off the band, but there is no daytime stress score in the SDK. Raw PPI makes our own HRV and stress possible.

## Alternatives

Polar numbers only (no stress). Our own numbers only (throws away Polar's tuned sleep and recharge).

## What it means

Every computed number records how it was made, so the app can explain it. Our formulas live in one place and are tested on recorded data.
