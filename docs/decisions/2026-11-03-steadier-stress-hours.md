# Steadier stress hours: 3-minute readings, the typical hour, and why an hour is empty

**Date:** 2026-11-03
**Who decided:** mine

## Context

Wearing the Loop all day, the owner saw empty stress hours and bars that looked either calm or maxed out. The backup (26 Oct – 3 Nov) showed the Loop records beat-to-beat almost continuously, but marks 83–92 % of daytime beats as movement. A reading needed 30 still beats inside one minute, so busy hours got none. Each bar was the hour's highest reading, so one minute set the hour: 19 % of bars sat at 100.

## Decision

`stress` version 4:
- A reading is 3 minutes of clock time with at least 30 pairs of neighbouring clean beats, gathered from every session in those minutes. Only true neighbours count: a pair never spans a dropped beat.
- The hourly bar is the hour's middle reading (median), and How it's worked out keeps the highest.
- A worn hour with no reading says why: mostly movement, the band off the skin, exercise, a workout, or too few clean beats.
- The Stress page draws every 3-minute reading as its own bar through the day, like Garmin's timeline, with real gaps where you moved. Journal's glance keeps the hourly bars. The owner asked for this after comparing with Garmin's stress screen.

## Why

On the backup, worn hours with a bar go from 77 % to 84 %, and bars at 100 from 19 % to 5 %, using only beats the band measured. The hours that stay empty had too few still beats in the whole hour; saying why beats guessing.

## Alternatives

Middle reading only (empty hours stay). The whole hour as one reading (97 % filled, but bars stop matching high-stress minutes and "now"). Counting the band's movement-flagged beats: rejected, the band repeats values it couldn't measure (guesses), and it squashes the range.

## What it means

Every day is worked out again. The calm baseline moves (on the backup 88 → 81 ms). Fewer, longer readings per day: a day with few readings can drop under the 10 the baseline needs.
