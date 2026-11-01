# One page per signal, shaped like Apple Health

**Date:** 2026-10-28
**Who decided:** mine
**Plan:** docs/plans/2026-10-28-one-page-per-signal.md
**Supersedes:** the "Body: weeks and months only … a separate view" part and the chart page of `2026-10-28-today-journal-body.md`; the "Body's Steps card still opens the chart" line of `2026-10-28-hourly-steps.md`

## Context

The same thing opened two different pages: a day page from Today and Journal, and a weeks/months chart page from Body. That felt wrong.

## Decision

Each thing (Recovery, Sleep, Stress, Heart rate, Steps, and the overnight signals) has one page: one chart with a D · W · M · 3M switch, a header over it (the day's number, or a plain average over the period, with the dates), a finger on the chart replacing the header with that point, ‹ › or a swipe moving one period, and the day's cards under the chart on D. Your normal stays as a shaded band behind W, M and 3M. Today and Journal open it on D for their day; Body's cards always show 4 weeks and open it on M (Body has no period switch of its own). Every other chart is a glance that opens the page, or is exempt (Heart fitness, widgets). Tapping a day in W, M or 3M opens D on it. The separate chart page is gone.

## Why

One thing, one place; Apple Health already taught the owner how this page reads.

## Alternatives

Day on top with "Over time" below on one scroll (two charts again). Keeping the chart page (the smell).

## What it means

Body still answers "how am I changing" with its cards, but a card opens the thing's page. Averages stay plain: no arrows, no best, no streak. Reversing means splitting the pages again.
