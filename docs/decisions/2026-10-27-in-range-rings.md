# Rings say "inside your normal", not a score

**Date:** 2026-10-27
**Who decided:** mine

## Context

Brainstorm round 2, kept through the redesign of the same day. The owner does not want Vesel to become a scoreboard: no self-optimisation, no score to chase.

## Decision

A ring is closed when that part of the day was inside the owner's own normal, and has a gap only when it fell below; the gap shows how far. Never above full; no best day, streaks or celebrations. The stress ring means calm. Today's big rings, the widgets, the calendar's little rings and the week charts' dots (filled = inside, hollow = below) all follow this. First week: a learning state (dashed). No data: an empty track.

## Why

A closed ring should mean "fine" everywhere, and a normal day should need no attention ("speak up only when something is off").

## Alternatives

One quiet mark per day, coloured only when off (calmer, but sleep and stress per day are hidden until tapped). Score rings as before (a fuller ring = a better score, which invites chasing).

## What it means

Changes the design system's score ring: the fill shows in-range, not a score. The sleep goal no longer fills the sleep ring. How "normal" is decided per ring is in `docs/how-it-works/days.md`.
