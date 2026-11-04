# Sleep

**Status:** Built: the Sleep page (opened from Today's Sleep line and Journal's Sleep card; the Night tab is gone) reads from the phone's database. HRV, lowest heart rate and breathing open night-by-night charts. The stages chart and the overnight heart-rate line scrub with a finger. The three new pages (In bed, Efficiency, Bedtime · wake) are built. Planned: a calmer D and stages over time (`docs/plans/2026-11-04-recovery-sleep-polish.md`), see "Planned" below.

> A night in detail, straight from the Loop. Recovery for the same night is its own page (`recovery.md`). Any earlier night is one tap away in Journal.

## Intent
First milestone: a morning sleep report read straight off the band.

## How it works
- Sleep stages, start and end come from Polar's sleep result, unchanged.
- A night belongs to the date you wake up on.
- Time asleep = time in bed minus wake periods (a night is worked out again after each read while Polar may still be finishing it). Efficiency = time asleep ÷ time in bed.
- Lowest heart rate = lowest 24/7 heart-rate sample during the night.
- HRV and breathing come from Polar's Nightly Recharge (see `recovery.md`).
- The Sleep line on Today and in the widgets = time asleep against your normal (from 1 SD under to 2 SD over your usual), not your sleep goal (`days.md`). The sleep goal is a band setting, editable in Body → About you (`pairing.md`). The Time asleep card has a "Your normal" row that explains the sleep line with its numbers. Every place that quotes the sleep normal (the meaning sheet's "Yours" line on Sleep, Recovery and Body) quotes this same range, from `InRange.sleep`.
- Today has no Right now card. The live heart rate (pulsing green dot while the app is open, else the latest stored reading with its time, or "Check the fit" without skin contact) is the "Now" row at the top of today's Heart rate page (`band-sync.md`).
- **The Sleep page** (pushed over Today, Journal or Body; its day is in its route; one page with D · W · M · 3M, see `days.md`): on D, the header ("7 h 40 m asleep" and the night line: "Last night", or "Monday night, October 26"), the stages chart with the overnight heart-rate line, the Sleep range line without a chevron, then the sleep part below. "No sleep recorded yet / this night" when there is none; paging to a day without a night shows that, never the previous night. `-VeselPage sleep -VeselPeriod d|w|m|3m` opens it in the Simulator.
- Until last night is stored, Today shows "Good morning — I'm up" as its first card when the band still reports sleep (or can't say), and every morning 03:00–12:00 unless the Loop was seen to end the night today, also with the Loop out of reach. "Still in bed" hides it for this morning (no card while the Loop records). Opening the app alone never ends the night.
- **I'm up (Built, `docs/plans/2026-10-30-calmer-morning.md`, phase 1):** works with the Loop out of reach: the tap is kept (also across launches) and the next read that reaches the Loop ends the night, unless the Loop already did. The card then becomes "Evaluating your night" until last night is stored; once a read didn't find the Loop: "Nothing for you to do. Your Loop gets the message as soon as it's near your phone." No "Couldn't reach your Loop" on I'm up. A tap the Loop never gets is dropped after 6 hours; a Loop that is near but refuses drops it and "I'm up" comes back. A read that can't reach the Loop keeps what it last said about sleep. "I'm up" never shows once last night is stored, even when the band can't say whether it still records. Not yet checked on the owner's iPhone.
- Every number has a "how it's worked out" line, one tap on its row.
- The Sleep page shows the night for the day in its route (`days.md`); the night for a past day is exactly that day's night ("No sleep recorded this night" when it has none). There is no Past nights list; pick a day in Journal.
- An overnight heart-rate line under the stages, on the same time axis, from the stored 24/7 samples (5-minute averages). A silence over 15 minutes is a gap in the line; a lone reading is a dot. No heart rate that night: "No heart rate recorded this night."
- Hold a finger on the stages or the heart-rate line, then drag: a vertical line follows it through both, and the page's header reads "03:12 · Deep · 51 bpm" (`-VeselScrub 03:12` starts there in the Simulator). The stage is Polar's at that minute, counted as the night's totals count it (before the first phase is awake); the heart rate is the stored reading nearest the finger within 7½ minutes (half the 15-minute gap that breaks the line), else "no reading", never a guess. Lifting the finger restores the header, and a light tick marks each 5 minutes the finger reaches. With VoiceOver, swipe up or down on the chart to move in 15-minute steps; it reads the same text.
- HRV, lowest heart rate and breathing on a night each open their page on D for that night (its week of nights is the chart; W, M and 3M are one tap away), from the first night; nights 2–7 show a faint dashed median line, with the learning wording ("Your usual range appears after 7 nights · N of 7"), then your usual band (see `recovery.md`). Nightly Recharge keeps its "how it's worked out" line.
- No sleep yet: "No sleep recorded yet. Wear your Loop tonight; the report appears after you wake up."

## Where it shows
- **Sleep as bars** (Built, phase 3 of `docs/plans/2026-10-30-calmer-morning.md`): on Body's Sleep card and the Sleep page's W, M and 3M, sleep is one blue bar per night (hours asleep, from 0) with your normal shaded behind, like Steps; the header still says "Average a night".
- Today's Sleep line opens the Sleep page for today; Journal's Sleep card opens it for the picked day. Journal's card shows the time asleep and where it sits against your normal ("Inside your normal"); empty: "No sleep recorded yet / this night".
- HRV, lowest heart rate and breathing on the page open their own pages on D, pushed on the same stack as the page.
- The low-recovery alert card opens the Recovery page.
- `-VeselPage hrv|lowestHeartRate|breathing` opens that page on D for last night in the Simulator.

## Meanings
- The stage rows (Deep, Light, REM, Awake) and Time asleep open their meaning (`meanings.md`) with the night's number (a stage's minutes and its share of your time asleep, Awake of your time in bed); how each is worked out sits folded inside it. In bed, Efficiency and Your normal still open in place.

## Planned: Sleep page polish
Planned (`docs/plans/2026-11-04-recovery-sleep-polish.md`).

- **D, top to bottom:** header ("7 h 40 m asleep", the night line); the stages and heart-rate chart; "The night": Bedtime · wake ("23:20 to 07:08", clock times, never a duration), In bed (value) and Efficiency (value and mark), each row opening its own page on D; "Your normal": a picture of your normal for time asleep as a shaded band, the night as a dot with its value and mark (replaces the Sleep range line and the "Your normal" row); Stages (Deep, Light, REM, Awake, opening their meanings); Overnight (HRV, Lowest HR, Breathing with value and mark, no chevrons). The "Time asleep" card with the second big figure goes. In bed and Efficiency used to sit below the fold inside that card.
- **W, M, 3M:** the time-asleep bars stay. Under them "Stages": one stacked bar per night, deep at the bottom, light, REM on top (awake left out), with a legend; a finger reads "Mon 2 Nov · Deep 1 h 20 m · Light 4 h 10 m · REM 1 h 30 m" into the header (only one chart's reading shows at a time), a tap opens that night. Then rows: In bed and Efficiency (plain averages of the period) and Bedtime · wake (the middle bedtime and wake), no marks, each opening its page on the same period.
- **New pages** (Built, phase 4b), each with D · W · M · 3M: **In bed** (bars from 0, your normal shaded), **Efficiency** (a line with a dot per night, your normal shaded), **Bedtime · wake** (one floating bar per night from bedtime to wake on a clock axis, evening at the top; no band). In bed's and Efficiency's normals are worked out on read from the 28 nights before each (at least 7), like Lowest HR, and not stored; "Show the numbers" explains them. In bed has no mark (a lie-in is not a warning). Efficiency counts only low nights: its normal runs from 2 SD under to 1 SD over the mean, above it is light green, under it orange, under 3 SD red. Bedtime · wake over a period is the median counted from 18:00, as the usual bedtime is ("Usually 23:20 to 07:08"; method `sleepTimes`, version 1, on read). `-VeselPage inBed|efficiency|bedtime` opens them in the Simulator.
- Signal pages' D (HRV, Resting HR, Lowest HR, Breathing, Skin temperature, In bed, Efficiency): the same picture at the top under the header (your normal as a band with its ends written, the night as a dot with its value and mark), then the nights as a line graph (In bed: bars), then "How it's worked out": "Your normal is the middle of your last 4 weeks of nights: 34–52 ms.", the glossary's good-or-bad sentence, and "Show the numbers" folded (the stored explanation with method and version).

## Do / Don't
- Don't rescore Polar's sleep stages.
