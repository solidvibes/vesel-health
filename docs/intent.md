# Intent

Why this project exists. The `interview` skill writes it; after that it changes only through a decision in `decisions/`.

## The problem

The Polar app has an old interface, and getting anything done takes many taps. Data only syncs after opening it, it nags ("did you finish sleeping?"), and there's no single answer to "how am I doing?". So the data from the Polar Loop goes unused.

## Who it is for

Just me. One person, one Polar Loop, one iPhone.

Not for other Polar owners, and not for athletes planning training. There are no other users to design for.

## Purpose

A health assistant that works in the background and tells me when something is not all right. If I want to, I can open it and see my data visually. Covers sleep, recovery, stress and exercise.

## Values

- My health data goes nowhere but my phone and my own Mac (the MacBook now, the 2014 Mac mini later).
- The phone is the main thing: it holds the data and does the calculations. The Mac is a backup and a place for heavier analysis.
- Quiet by default. It speaks up when something is off.
- Calm, minimal, clean to look at.

## Constraints

- iPhone only, plus home-screen and lock-screen widgets. My own Mac at home is the server: the MacBook now, the 2014 Mac mini later.
- Built by the owner with AI. This is the owner's first iOS app.
- Budget: the Apple Developer account the owner already has. Nothing else.
- No deadline. First milestone: a morning sleep report read straight off the band.

## Business model

None. Personal tool.

## Never

- Never send health data to Polar's, Apple's or any other cloud.
- Never depend on the Polar app being opened.
- Never nag.
- Never show a number it can't explain.
- Never turn health into a score to chase.
- Workout load is not added up over days or weeks for now (no weekly load, no bests, no streaks; see `ideas/training-load-trends.md`).

## Success

I use it myself.

## Out of scope

- Other users, accounts, the App Store.
- Android or the web.
- Training plans and athlete load over time (Intervals.icu territory). Each workout's own load, as Polar measured it, is in (`decisions/2026-11-03-workouts.md`).
- Reading data through Polar's or Apple's clouds.
