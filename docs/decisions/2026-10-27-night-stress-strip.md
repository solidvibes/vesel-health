# A week strip on Night and Stress; learning rings dimmed

**Date:** 2026-10-27
**Who decided:** mine

## Context

After using the week-strip build on the iPhone, the owner found Night's single nested ring less useful than seeing the week, and the dashed learning rings harder to read than a dimmed ring.

## Decision

Night and Stress get a week strip under the title: seven days, each with that tab's small rings (Night: recovery and sleep; Stress: calm), the picked day highlighted. Tap a day to pick it; swipe the strip to move a week. The title still opens the month calendar. On Night the strip replaces the nested ring and its legend; the summary line stays. Stress shows the strip only when it has data. Today keeps no strip.

A ring that is still learning your normal is drawn as a full dimmed circle in its colour, not dashed.

## Why

The week at a glance is what the owner looks for on Night and Stress; Today stays about today. A dimmed ring reads as "not judged yet" without the busy dashes.

## Alternatives

Strip above the big nested ring (more to scroll past). A fixed week with no swiping (one more tap to go back). Keeping dashed learning rings.

## What it means

Partly supersedes `2026-10-27-day-calendar.md` (no strip) for Night and Stress, and the "learning = dashed" line of `2026-10-27-in-range-rings.md`.
