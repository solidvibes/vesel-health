# Hourly steps are back, on Journal and a Steps page

**Date:** 2026-10-28
**Who decided:** mine
**Plan:** docs/plans/2026-10-28-round8.md
**Supersedes:** the "drop hourly steps" part of the 2026-10-27 call (see `2026-10-28-soft-background-and-steps.md`, which recorded it)
**Superseded in part by:** 2026-10-28-one-page-per-signal.md (Body's Steps card still opens the chart)

## Context

Round 7 showed steps only as a total on Journal. The owner looked at the options again and wants to see when in the day he moved.

## Decision

- Journal's Steps card shows the total and small bars per hour, 00:00 to 24:00, and opens a new Steps page for that day.
- The Steps page shows the day's total (the daily summary's), a bar per hour, and the last weeks. Today's Steps card opens it; Body's Steps card still opens the chart.
- No goal, no busiest hour, no best, no streak (`2026-10-27-no-score-to-chase.md`).

## Why

When you moved is part of how the day went, and it needs nothing new from the band.

## Alternatives

Total only (round 7). Hourly bars on Journal without a page.

## What it means

Hourly steps are read from the per-minute step samples already stored in `raw_export`; no migration and no new table. Bars for today can trail the total slightly: the two are read separately and not reconciled.
