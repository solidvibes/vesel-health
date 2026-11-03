# Recovery and Body

**Status:** Built: Today, Journal and the Recovery page read from the phone's database. Body (4 weeks / 3 months, every signal with its normal as a band that moves with you) is built from the first night, with a range picker in each chart. Today's headline covers all three lines.

> How recovered you are, as Polar's Nightly Recharge, with each contributor against your own normal.

## Intent
Polar's numbers as-is, plus a personal comparison that explains them (decision `2026-10-26-polar-plus-own-analysis.md`).

## How it works
- **Score:** Polar's Nightly Recharge status 1–6 with Polar's word (very poor, poor, compromised, OK, good, very good). Stored as given (`recovery.status`, version 2: "Polar's Nightly Recharge says OK (4 of 6)."). The Recovery line follows the in-range rule in `days.md`: OK or better is inside.
- **Contributors**, each against your 28-night range:

  | Contributor | Source |
  |---|---|
  | HRV | Polar's nightly RMSSD (ms) |
  | Resting HR | 60 000 ÷ Polar's nightly mean beat interval (bpm) |
  | Sleep | Time asleep |
  | Breathing | 60 000 ÷ Polar's nightly mean breath interval (breaths/min) |
  | Skin temperature | Mean during sleep, shown as difference from usual (°C, or °F with US units) |

- **Your range** (`range28`, version 1): mean ± 1 standard deviation (of those nights, not an estimate) of the previous 28 nights, not counting the night itself. Beyond 2 SD = "well below/above". **Sleep is the exception:** its row, arrow and stored explanation (`recovery`, version 2) use the same normal as the Sleep line (`InRange.sleep`): from 1 SD under to 2 SD over the mean. Inside it reads "usual"; under 1 SD below "shorter than usual" ("much shorter than usual" beyond 2 SD below); only past 2 SD above "longer than usual" (grey, never "much"). For "furthest from usual" a sleep night inside its normal counts as 0, and one outside counts from the edge of its normal, so sleep is named only when it is outside it. Fewer than 7 earlier nights: "Your usual range appears after 7 nights · N of 7" (N = earlier nights so far; on the first night without the count, never "0 of 7"). Every learning line on screen (Today's lines, contributor rows, night-by-night captions, the Body cards, the widgets, the headline's why line) uses this one wording; stress and calm say "Your stress levels appear after 7 days · N of 7".
- **Headline** (`headline`, version 4): Today's and the medium widget's sentence on recovery, sleep and stress, plus one second line saying why. First matching rule wins. Worked out when the screen opens from the lines, Polar's status and the contributors; not stored. Voice: plain, positive, never blaming.

  | Rule | When | Sentence | Second line |
  |---|---|---|---|
  | 1 | no night stored and no stress judged | (none: Today's empty state) | |
  | 1b | no night stored, stress judged today | No sleep recorded last night. | "A calm day so far." or the stress numbers |
  | 2 | recovery or sleep still learning | Getting to know you. | (none: the check rows say it) |
  | 3 | a night, Polar hasn't scored it | Polar hasn't scored your recovery yet. | time asleep |
  | 4 | recovery below, Polar 3 | Recovery is lower than usual today. | the contributor furthest from usual, then "Sleep was also shorter/longer than usual." and "Stress is also above your normal." for other lines outside; with none of these: "None of last night's readings stood out on its own; Polar weighs them together." |
  | 5 | recovery below, Polar 1 or 2 | Recovery is low today. | as rule 4 |
  | 6 | sleep below | You slept less than usual. | "7 h 40 m is under your usual of 7 h 50 m to 8 h 40 m." then any stress line |
  | 7 | sleep above | You slept longer than usual. | "9 h 55 m is over your usual of …; it can mean catching up, or your body asking for rest." then any stress line |
  | 8 | stress above | More stress than usual today. | "45 m of high stress so far; your usual is up to 30 m." |
  | 9 | every line with data is inside | "Things look good today." on Polar 4, else "Everything looks great today." | what is inside: "Recovery is good, your sleep was right in your normal, and a calm day so far." |

  **`headline` version 4 (`workouts.md`):** rules 4 and 5 name yesterday's workout when Polar rated it 3 or higher of 5 (the highest cardio load among those): "Low recovery after yesterday's ride.", "Recovery is lower than usual after yesterday's run." A workout without Polar's rating, or hidden, isn't named.

  What tends to help for what was off is on the line's page, never on Today (`what-helps.md`).
- **Recovery sentence** (`recoverySentence`, version 1): Polar's own table, on the Recovery page's card only: 6 "You're well recovered.", 5 "Recovery is good.", 4 "Recovery is OK.", 3 "Recovery is lower than usual.", 1 or 2 "Recovery is low.", no status but a night "Polar hasn't scored your recovery yet."; the why names the contributor furthest from your usual (beyond 1 SD), then the time asleep ("HRV 38 % below your usual; 7 h 40 m asleep."), "Everything is within your usual range" when none, or the learning words.
- Every number keeps how it was made (method, version, inputs); "How it's worked out" shows it. A new method version is recomputed for every stored night on the next read (`recovery` version 2 recomputed every stored contributor once).
- **Body:** no period menu: every card shows the last 4 weeks. Two groups: Recovery, sleep and stress (Recovery on Polar's 1–6, Sleep in hours asleep, Stress as high-stress minutes a day) and Overnight (HRV, Resting HR, Lowest HR, Breathing, Skin temperature). Each card shows the latest night's value and a chart of the range; a card opens the signal's page on M (`docs/plans/2026-10-28-one-page-per-signal.md`). A night or day with no number is a gap, never joined across.
- **Body from the first night:** there is no seven-night gate; cards and charts show from the first night, and only the normal band waits for 7 earlier nights. Until then each chart (HRV, Resting HR, Lowest HR, Breathing, Sleep, Skin temperature) shows a faint dashed line at the median of the nights so far (the last 28, from night 2 on), captioned with the learning wording (N = earlier nights, as everywhere else; no count on the first night); the band replaces it from 7 earlier nights. Worked out on screen, not stored; Polar's baseline fields are not used. With nothing stored: "No data yet · Body starts after your first night with the Loop."
- **Two more rows:** Lowest HR (the lowest 24/7 heart-rate sample during the night, see `sleep.md`) and Breathing (60 000 ÷ Polar's nightly mean breath interval). Both are already stored per night. Breathing's usual is its stored 28-night range. Lowest HR's usual is worked out when the chart opens, by the same rule (`range28`: mean ± 1 SD of the previous 28 nights, at least 7), and is not stored; the chart says so in words.
- **The period switch** lives on the page only: D · W · M · 3M (a night, 7 days, 4 weeks, 3 months; windows end on today, ‹ › move one period), see `days.md`. Recovery's W, M and 3M header is the most frequent verdict ("Mostly OK"; the newer night wins a tie), never an average or a count of good nights.

## The Recovery page
The Recovery page (pushed over Today, Journal or Body; its day is in its route; one page with D · W · M · 3M) shows on D the header (Polar's verdict, "Good · 5 of 6", with the night's date), the 7 nights ending on that night with that night drawn full and the others faded (hold a finger on it, then drag: each night's own word; tap a night to open D on it), the Recovery range line without a chevron, and one card. Journal's Recovery card shows Polar's word and "N of 6" with where it sits against your normal, the recovery line and the contributor furthest from your usual (else HRV), and opens the page for the picked day. Top of the card: "Recovery" (opens what it means) and, right, Polar's verdict in words with "N of 6" ("Good · 5 of 6"; nothing there while Polar hasn't scored the night). Then the sentence (Polar's table) and the one why line. "What went into it": a row per contributor, name left and on the right the word against your usual and the value ("higher than usual · 48 ms"; skin temperature "usual · +0.2 °C", or "+0.4 °F" with US units; its row, its "Yours" line and the headline's why line follow the units, while "How it's worked out" stays in the stored °C), each with an arrow. The words are much lower than usual / lower than usual / usual / higher than usual / much higher than usual; while learning the row shows the value and the learning wording. The arrow's colour follows the good side (the words stay in text colour): HRV higher, resting heart rate lower and sleep higher are green, the other side is orange, within your usual is grey; a much longer night than usual is grey (it can mean catching up or being unwell); breathing and skin temperature have no good side and are always grey. The words and arrow always say it too. A key line under the rows explains the colours, with "usual" opening its meaning. A row opens that contributor's meaning with "Yours" ("Last night: 48 ms, higher than your usual (34–52 ms)."); its "Night by night" button closes the sheet and opens that contributor's page on M. Last, "How it's worked out" opens in place onto Your normal, Nightly Recharge, the sentence and each contributor. Under the card, "What tends to help" when something was off (`what-helps.md`). Today's recovery line and the low-recovery or unusual-resting-heart-rate alert card open the page for today; Body's Recovery card opens the Recovery page on M. `-VeselPage hrv -VeselPeriod m` opens a contributor's page in the Simulator.

## Also built (week-strip plan)
- The Recovery line on screen shows whether the night was inside your normal (`days.md`). Since `recovery.status` version 2 each stored night is recomputed on the next sync, and its row goes to the Mac backup once more.
- **The moving normal:** every Body card and the page's W, M and 3M chart draw a value per night (a line with a dot; Stress as bars) over a shaded band that follows each night's own normal: for each night, low…high of the 28 nights before it. A night with no normal yet (the first 7) has no band, and a night with no number is a gap. The band's source: Recovery 4…6 (Polar's OK and better; Polar compares with your usual itself; a night is drawn at Polar's indicator plus its sub-level ÷ 100); Sleep, HRV, Resting HR, Breathing and Skin temperature the stored `usualMean` ± `usualSD` of that night's contributor; Lowest HR worked out on read per night with `PersonalRange` over the 28 nights before it (at least 7), not stored; Stress 0 up to that day's allowance (`DayLines.calm.normal.high`). A dot outside its band is hollow on the page's chart. Every chart draws the whole period (the x axis runs from the first day's start to the end of the last day, nights at the day's midday, today's at the earlier of midday and now), with a faint grid, 3 numbers on the trailing side and dates along the bottom (every 7th day "12 Oct" on 4 weeks, the 1st of each month on 3 months). VoiceOver reads the latest value and "your normal now 34–52 ms".

## Do / Don't
- Don't replace Polar's verdict with our own score.
- Don't show a contributor verdict before 7 nights.
