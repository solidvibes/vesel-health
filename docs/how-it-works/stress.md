# Stress

**Status:** Built: the Stress page (opened from Today's Stress line, Journal's Stress card and the long-high-stress alert card; the Stress tab is gone), and Today's stress line read from the phone's database. Thresholds provisional.

> How stressed today has been, worked out on the phone from the Loop's beat-to-beat data.

## Intent
Polar's SDK has no daytime stress score; Vesel computes its own (decision `2026-10-26-polar-plus-own-analysis.md`).

## How it works
- Input: the Loop's automatic 24/7 beat-to-beat (PPI) sessions. How often the Loop records them is not known until the real band's data report is read.
- Cleaning: drop beats flagged for movement or no skin contact, beats outside 300–2000 ms, and jumps over 20 % from the previous kept beat. A beat the band sent no status for is kept: unknown contact is not "no contact".
- A reading needs ≥ 30 clean beats. Readings during high activity are skipped (exercise isn't stress).
- Only readings from 06:00 to 22:00 count; night readings are sleep.
- A reading is one session, or a 60 s slice of a longer one.
- Workouts (`workouts.md`, `stress` version 3): a reading that overlaps a workout the Loop recorded is skipped, unless the owner marked it "Not a workout"; How it's worked out says how many were inside workouts. A stored or changed workout, or the owner's fix, recomputes its day on the next pass. Planned: the fix recomputes at once, from the Workout page.
- Exercise: the band's high-activity mark, or a heart rate above resting + 40 % of the reserve (220 − age), within 2 minutes of the reading.
- Each reading: ln(RMSSD), compared to your calm baseline (80th percentile of the 14 days before, never the day itself) and floor (5th percentile) → level = (baseline − value) ÷ (baseline − floor) × 100, held to 0–100. Only days with at least 10 readings go into the baseline.
- Percentile: sort the values; position p × (n − 1), straight line between the two nearest values.
- If baseline and floor are equal, a reading below the baseline is 100 and any other is 0.
- Calm below 34, moderate 34–66, high 67 and up, on the level rounded to a whole number as the screens show it.
- High-stress minutes per day add up high readings (each counts until the next reading, at most 15 min; the last one for its own length).
- The busiest 2 hours: the most high-stress minutes in 2 hours starting at a high reading, counted the same way but cut at the end of the 2 hours. It feeds the long-high-stress alert (version 2 of `stress`).
- "Now" = the latest reading if under 30 minutes old.
- Needs 7 earlier days with at least 10 readings each first: "Your stress levels appear after 7 days · N of 7" (N = earlier days so far, no count on the first day).
- The Stress page says "Based on N readings today"; hours with no reading have no bar.
- **The Stress page** (pushed over Today, Journal or Body; its day is in its route; one page with D · W · M · 3M, see `days.md`): on D, the header ("45 m high stress", "No high stress"; today "8 m high stress" with "Today · so far"), the hourly bars (hold a finger on them, then drag: the header reads "14:00–15:00 · High, 72" or "no reading"; `-VeselScrub 14:00` starts there in the Simulator), the Stress range line without a chevron, the headline and peak line, and How it's worked out with Your normal, then "What tends to help" when calm was above your normal. The heart-rate line and Last 7 days are not on it (heart rate has its own page). While learning: the learning wording and its paragraph.
- The Stress page shows the day in its route (`days.md`); a day with nothing shows as empty. A past day shows its hourly stress.
- Today's headline stays "Calm now." (and the other "now" sentences). A past day has no "now": its headline is its high-stress minutes, "45 m of high stress." or "No high stress.", and none when the day has no stress numbers; the peak line is the same. Captions say "on this day" instead of "today".
- Every stored number keeps its inputs: baseline, floor, readings, and what cleaning dropped. All thresholds live in `StressThresholds`.
- Gaps in data show as gaps.
- Today's Stress line: inside when the day's high stress stayed at or under your usual, above it otherwise (`days.md`). The word beside it still says the stress now. The "How it's worked out" card has a "Your normal" row for the day shown, with the allowance and the day's minutes.

## Recomputing
- The stress pass works out the last 3 days with beats on every sync, days with beats but no numbers yet, days stored under an older method version, and any day whose beats or heart rates were stored after its numbers (from `band_ledger.stored_at`, later than that day's `stress.readings` time): a sync that re-reads an older day after a long gap recomputes it. Each recomputed day also refreshes the later days whose 14-day baseline it feeds. A day recomputed to the same numbers keeps its numbers and its backup mark; only its `stress.readings` time moves on, so it is not picked again.

## On Body
- Body's Stress card shows each day's high-stress minutes as bars over a band from 0 up to that day's allowance (`DayLines.calm.normal.high`); a day with no stress numbers has no bar. Its card opens the Stress page on M. The stress level bars of Trends (15-minute, hourly and daily peaks and averages) and the 5-minute stress day page are gone; the Stress page's hourly bars stay.

## Do / Don't
- Don't fill gaps with guesses.
- Don't count exercise as stress.

## Open questions
- Exact thresholds may move after the first week of the owner's real data (the starting values are the plan's).
