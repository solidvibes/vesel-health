# Range lines instead of rings

**Date:** 2026-10-28
**Who decided:** mine
**Supersedes:** 2026-10-27-in-range-rings.md (how the state is drawn, and sleep above usual)

## Context

A ring says "close me". Recovery swings night to night and calm should never "close". The owner liked a line with a top and a bottom: anywhere between is good.

## Decision

Recovery, Sleep and Calm are drawn as a range line: a track, your normal shaded, a dot for you. Inside the shaded part = fine; outside = a hollow dot. Too little and too much both count as outside (sleep is off when well above your usual: more than 2 SD over the mean, while below stays under mean − 1 SD; calm only has a top; recovery only a bottom). Used on Today, the full pages, widgets and the lock screen; the round lock-screen spot bends the line into an arc. The app icon keeps its one ring.

The normal is always your last 4 weeks, so it moves with you (start training and the calm top rises over those weeks). Body and the full pages show the normal moving as a shaded band over time.

## Why

Shows "inside your normal" directly and never looks like a goal to fill.

## Alternatives

Keep rings (reads as "fill it"). Words only (loses how far off).

## What it means

The ring component, the rings in the calendar and strip, and the widget rings are replaced. The in-range rule in `docs/how-it-works/days.md` changes for sleep above usual.
