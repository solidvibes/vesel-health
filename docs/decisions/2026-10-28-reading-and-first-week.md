# Show the Loop being read, and count down the first week

**Date:** 2026-10-28
**Who decided:** mine

## Context

While the app read the Loop, Today showed grey boxes for up to a minute; in the first week the rings were dimmed with no sense of when they would fill.

## Decision

- **Reading:** the last known numbers stay, faded, and a short list ticks off each part as it arrives (Loop found, heart rate, last night N of M parts, stress today). The live heart rate shows with the green pulsing dot. No flashing card. The list folds away when done.
- **First week:** each line shows a row of check marks in its colour (recovery green, sleep blue, calm orange), one per night or day that came in, and how many more are needed (with the day it completes). Calm's row is longer (about two weeks).

## Why

Shows it is working, and when the normal will appear.

## Alternatives

Grey boxes plus a progress line. Dimmed rings as before.

## What it means

Supersedes the "learning = dimmed ring" line of `2026-10-27-night-stress-strip.md`.
