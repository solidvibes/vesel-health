# Colour says where you are against your normal

**Date:** 2026-11-04
**Who decided:** mine
**Supersedes:** the "outside = a hollow dot" part of `2026-10-28-range-lines.md` on the Recovery, Sleep and signal pages; the "Green: good side, orange: other side, grey: within" key on Recovery; the range line row on the Recovery and Sleep pages' D (Recovery drops it, Sleep shows its normal as the signal pages' picture)

## Context

On the phone, Recovery's list read as too much text: an arrow, a word, a number per signal, and grey for "usual". The owner wanted to see at a glance what is fine and what is off.

## Decision

Every value compared with your normal gets one mark, colour plus symbol:

- darker green ✓: inside your normal, no arrow
- lighter green with an arrow: outside it on the good side
- orange with an arrow: outside it on the side that matters
- red ‼: well outside it (the existing "well below / well above" step)

Arrows show only outside your normal. Colour is never alone: the symbol and VoiceOver say the same thing. Recovery's top says it in words ("Well recovered") with the date line; no score, no Polar "x of 6" there (it moves into how it's worked out). Rows that open a page have no chevron; the whole row is the button.

## Why

Green should mean "fine" and need no reading; only what is off should catch the eye ("speak up only when something is off").

## Alternatives

Orange on either side of the normal (a great night would look like a warning). A single 1–100 recovery number (rejected: reverses `2026-10-27-no-score-to-chase.md`).

## What it means

Today, widgets and the lock screen keep their current range lines for now. `docs/design/system.md` gains the four marks.
