# A much softer background, and steps in three places

**Date:** 2026-10-28
**Who decided:** mine
**Plan:** docs/plans/2026-10-28-round7.md

## Context

Round 6 left three strong colour blobs behind every screen. The owner looked at three options (today's blobs, much softer, plain) and at steps in three places, and answered on a visual page.

## Decision

- Background: one faint wash at the top right, mostly sleep blue (about 10%) with a fainter touch of recovery green (about 7%) over it; nothing in the lower part. Today's "something's off" keeps a stress-coloured glow at the top, quieter (about 18%, was 40%).
- Today: a small Steps card under the Heart rate card: today's steps so far with "so far · read HH:mm". No goal, no comparison. It opens the Steps chart.
- Body: a Steps card near Stress: steps per day as bars over your moving normal (the same 28-day normal as every measure), today's bar lighter. It opens the chart page with the other Body charts' ranges.
- Journal: one "Steps" line with the day's total on the Day section. No hourly bars (the owner dropped hourly steps on 2026-10-27; brought back the same day, see `2026-10-28-hourly-steps.md`).
- Steps use the muted text colour; no new colour.

## Why

The wash keeps the glass feel without competing with the content. Steps are worth seeing, but only as a count against your own normal: never a target, a streak or a best.

## Alternatives

Today's blobs (too strong); no background colour at all (cold). Journal steps by hour (reverses the 2026-10-27 call and needs a new table).

## What it means

No new data is stored; steps come from the daily summary already kept in `activity_day`. The "Surfaces are Liquid Glass ..." line in `docs/design/system.md` changes. Steps never get a goal line, a best day or change arrows (`2026-10-27-no-score-to-chase.md`).
