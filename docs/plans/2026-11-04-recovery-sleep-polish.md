---
status: not-started
---

# Recovery and Sleep polish: one colour language, less text, every number opens its page
**Date**: 2026-11-04
**Status**: Approved
**Touches**: `docs/decisions/2026-11-04-colour-against-your-normal.md`, `docs/decisions/2026-10-28-range-lines.md`, `docs/decisions/2026-10-28-one-page-per-signal.md`, `docs/decisions/2026-10-27-no-score-to-chase.md`, `docs/design/system.md`, `docs/design/screens.md`, `docs/how-it-works/recovery.md`, `docs/how-it-works/sleep.md`, `docs/how-it-works/days.md`, `docs/how-it-works/meanings.md`, `.agents/skills/layers/SKILL.md`

## TL;DR
- Six phases, one PR each, inner layers first: 1 marks, 2 Recovery, 3 signal pages, 4a sleep reads, 4b new pages, 5 Sleep page.
- Phase 1: VeselCore `NormalMark` (inside ✓, better ↑↓, off ↑↓, far ‼) and `NormalScale` (where band and dot sit).
- Phase 1: eight colour sets (four chips, four symbol inks), every chip ≥ 3:1, every symbol ≥ 4.5:1; `MarkBadge`.
- Phase 2: Recovery D header "Well recovered" + date only; no "x of 6", no range line, no sentence.
- Phase 2: "What went into it" rows = name, value, mark; whole row opens that signal's page on D.
- Phase 2: Recovery charts' y-scale fits the values shown; W/M/3M header "Most nights · Good recovery".
- Phase 3: signal pages' D: band-and-dot picture at the top, then the nights' line graph, then a shorter "How it's worked out".
- Phase 3: page charts (not Body's compact cards) fill outside dots in their mark colour instead of hollow.
- Phase 4a: read-only queries for In bed, Efficiency, stages and bedtimes, read only where shown; `SleepTimes`; glossary.
- Phase 4b: In bed, Efficiency, Bedtime · wake pages (D · W · M · 3M); In bed has no mark; Efficiency counts only low nights.
- Phase 5: Sleep D: In bed / Efficiency / Bedtime · wake right under the chart, then the normal picture.
- Phase 5: Sleep W, M, 3M: time-asleep bars stay; stacked deep/light/REM bars and three rows under them.
- Chart types: lines for nightly signals and efficiency, bars for durations, stacked bars for stages, floating bars for bedtime.
- No contract risk area touched: nothing leaves the phone, no migration, nothing deleted.

## Context
Owner's feedback on the phone, 4 Nov 2026, worked through in a brainstorm and accepted (mockup `.solidvibes/visuals/recovery-sleep-polish.html`; decision `docs/decisions/2026-11-04-colour-against-your-normal.md`). Recovery's card read as too much text: an arrow, a word and a number per signal, grey for "usual", a colour key, a big sentence, a why line and Polar's "x of 6" twice. The owner wants to see at a glance what is fine and what is off, and to land on a signal's page with one tap. The Recovery chart wastes height on an always-1–6 scale. On Sleep, the owner couldn't find In bed and Efficiency: they exist on D, but inside a "Time asleep" card under the stages chart, the range line and a second big "Time asleep" figure, below the fold on the phone. Sleep's W, M and 3M only show time asleep.

What exists today (read from the code):
- Per night, already stored in `computed_metric`: `sleep.inBed`, `sleep.efficiency`, `sleep.stage.<deep|light|rem|wake>`, `sleep.asleep`, the contributors, `sleep.lowestHr`, `recovery.status`. Bedtime and wake are `sleep_night.start_at` / `end_at`. So nothing new is stored.
- `TrendsSnapshot.kinds` (VeselStorage) reads only the trended kinds, for every `BodyModel`; In bed, Efficiency, the stages and sleep start/end are not read over a window.
- `ContributorReading.verdict` gives `wellBelow / lower / usual / higher / wellAbove`; sleep's `wellAbove` means only "above its normal" (past 2 SD), never "much".
- `Contributor.goodSide` / `GoodSide` are used only by `ContributorRow` and tested in `RecoveryContributorsTests`.
- `RecoverySentence.make` is used only by `RecoveryModel`; `driver` and `describe` are also used by `Headline`, `JournalModel` and `WhatHelps`. `Headline.noneStoodOut` is private.
- `LineScale` (VeselCore, `InRange`) already places a normal and a dot on a 0…1 track, clamping past the ends; only recovery, sleep and calm build one.
- `SignalChart` is shared by Body's compact cards and the pages (`compact: false`); its recovery y-domain is fixed `1...6`, axis values `[1, 3, 6]`.
- `UsualBedtime` works out a median sleep start counted from 18:00 inline.

## Constraints
- Rules (load them): `AGENTS.md`, `.agents/skills/layers/SKILL.md`, `.agents/skills/testing/SKILL.md`, `.agents/skills/data/SKILL.md` (phase 4a reads health data over a window).
- Skills: `sv:accessibility` (`/Users/viktorstojanov/.claude/plugins/cache/solid-vibes/sv/0.1.4/skills/accessibility/SKILL.md`) and `sv:writing` (`/Users/viktorstojanov/.claude/plugins/cache/solid-vibes/sv/0.1.4/skills/writing/SKILL.md`): every phase changes what the owner sees and reads.
- Non-negotiables that bite here: every number can be explained (stored or on-read explanation one tap away on every page, including on-read normals); never a score to chase (no 1–100 number, no bests; W/M/3M rows are plain averages, no marks on averages); never nag (only what is off gets orange or red; In bed and Efficiency are tuned not to flag ordinary nights).
- Colour never alone: each mark is colour + symbol + VoiceOver words; chart dots outside the normal are also told apart by their place against the shaded band, and VoiceOver says the mark's words.
- Layers: a mark's kind and where a band and dot sit come from VeselCore (`NormalMark`, `NormalScale` → `LineScale`); views only draw. Theme views take plain values (Theme is compiled into the widget extension). Meaning text only in `Glossary`. Learning words only from `LearningText`. Page charts only inside `SignalPage`; each new chart says it is on a thing's page.
- Out of scope: Today, widgets, lock screen, Journal, Body's cards (they keep hollow dots and range lines for now), the parked bug `docs/ideas/page-opens-under-title-bar.md`, anything sending data off the phone.
- Risk areas (contract `risk`): none touched. Phase 4a adds read-only queries; no migration, no upload change, no delete.
- Packs: none (`docs/stack.md` has no `## Packs`).

## Approach

### The four marks (phase 1)
`NormalMark` in VeselCore:

| Mark | When | Chip (light / dark) | Symbol ink (light / dark) | Symbol | VoiceOver |
|---|---|---|---|---|---|
| inside | verdict `usual` | #1E7A44 / #4ADE80 | #FFFFFF / #111113 | `checkmark` | "inside your normal" |
| better | outside, on the better side (any distance) | #36975A / #3E8F5C | #111113 / #111113 | `arrow.up` or `arrow.down` | "above your normal, the good side" / "below …" |
| off | `lower`/`higher` on the side that matters | #D9621B / #FF9A52 | #111113 / #111113 | `arrow.up` or `arrow.down` | "above your normal" / "below your normal" |
| far | `wellBelow`/`wellAbove` on the side that matters | #C42B1C / #FF7B6E | #FFFFFF / #111113 | `exclamationmark.2` (‼) | "well above your normal" / "well below …" |

Contrast, computed from the hex values (the chip colour is also the chart-dot colour, so each chip must reach the 3:1 for chart marks):
- Symbol on chip, light: inside 5.35, better 5.15, off 5.13, far 5.66; dark: 10.8, 4.75, 9.0, 7.5 (all ≥ 4.5).
- Chip/dot on the light background #F3F3F1: inside 4.8, better 3.3, off 3.3, far 5.1; on white: 5.35, 3.66, 3.68, 5.66.
- Chip/dot on the dark surface #1A1C20: inside 9.8, better 4.3, off 8.1, far 6.8; on the dark background #0E0F11: 11.0, 4.8, 9.1, 7.5.
- "Darker / lighter green": light mode inside #1E7A44 vs better #36975A; dark mode the inside green is the brighter one and better the muted one. They differ by symbol (✓ vs arrow) as well as shade. In light mode the better dot is close to the recovery data green of inside dots on charts: on purpose, both mean "fine"; the dot's place outside the band and VoiceOver tell them apart.

`MarkBadge` (Theme): a circle sized with `@ScaledMetric` (24 pt at the default size, relative to `.footnote`) inside a ≥ 48 pt row, the SF Symbol at the small type size. Learning (fewer than 7 earlier nights) has no mark: the learning words show instead.

Mapping, per thing (`better` = which side is the better one):
- HRV: higher. Resting heart rate: lower. Lowest heart rate: lower (the glossary says "Lower than your usual is usually a sign of a restful night").
- Sleep: higher, but above its normal (`wellAbove`, past 2 SD) is **off ↑**, never better and never far. Below: `lower` off ↓, `wellBelow` far ‼.
- Breathing, skin temperature: no better side; either side outside is off, beyond 2 SD far.
- Efficiency and In bed: see phase 4b (gate item).
- Recovery (Polar's 1–6): 4–6 inside, 3 off ↓, 1–2 far ‼.
- Far only on the side that matters; far on the better side stays better (a great night never looks like a warning).

`NormalScale` in VeselCore: from a value and its normal (low…high, in the value's units) returns a `LineScale` on a track one normal-width either side of the normal (never under 0 for durations and percentages, never over 100 for efficiency), clamped at the ends, the same way `InRange.sleep` builds its track. Used for the contributors, Lowest HR, In bed, Efficiency and time asleep (sleep keeps `InRange.sleep`'s own scale).

### Recovery D (phase 2)
Header: short verdict and the existing night line ("Well recovered · Last night"); the scrub reads the touched night's short verdict and date. Short words, `RecoveryStatus.verdict` in VeselCore: 6 "Well recovered", 5 "Good recovery", 4 "Recovery OK", 3 "Lower than usual", 1–2 "Low recovery"; unchanged "Evaluating…" and "Not scored yet". W, M, 3M header: a small "Most nights" over the most frequent short verdict ("Good recovery"), newer night wins a tie, as now; so the header and the scrub use the same words.

Then the 7-nights chart, y-scale fitted (below). Then one card: "What went into it", a row per contributor: name left, value and mark right (skin temperature as its difference, "+0.9 °C"); while learning, the value and the learning words, no mark. No chevrons, no colour key. A row is one button opening that signal's page on D for that night (`PageRoute(kind, day: night)`), like Sleep's Overnight rows. VoiceOver: "HRV, 62 ms, above your normal, the good side", hint "Opens HRV". The meaning sheet is on the opened page's title.

One muted line under the rows, from VeselCore (`RecoverySentence.quietLine(status:contributors:)`, reusing `Headline`'s "None of last night's readings stood out on its own; Polar weighs them together.", made shared): shown only when Polar says 3 or lower, at least one row has a mark, and every row with a mark is `inside` (not when a row is better, off or far; not when every row is learning).

Then "How it's worked out" (folded): Polar's Nightly Recharge first (its text already says "OK (4 of 6)"), Your normal, each contributor; "The sentence" goes. The Recovery range line row under the chart goes (the header word and the chart's band say it). What tends to help stays under the card.

`RecoverySentence.make` and its sentence table go; `driver` and `describe` stay.

**Chart y-scale:** for recovery the y-domain fits the points and their band like the other line charts (`low − pad … high + pad`, never under 1); axis numbers are the whole Polar steps inside it. Same rule on W, M, 3M and Body's Recovery card: it is one chart.

### Signal pages (phase 3)
D of HRV, Resting heart rate, Lowest heart rate, Breathing, Skin temperature (and from phase 4b In bed and Efficiency), all `NightlyDayPart`, top to bottom: the header; the picture; the nights' graph (`NightsChart`, the 7 nights as a line with dots over the band, as today; In bed keeps its bars, a duration); then "How it's worked out". The "Your normal" row card goes.
1. The picture, at the top under the header (`NormalPicture`, Theme, in a glass card): draws a `LineScale` from `NormalScale` plus plain strings: the track, your normal shaded, its low and high written under its ends, the night as a dot filled in its mark colour, its value written over it with the `MarkBadge`. At accessibility text sizes the labels stack under the track instead of beside the ends. VoiceOver: one element, "Last night 62 ms, above your normal, the good side. Your normal 34 to 52 ms."
Then "How it's worked out", one card:
2. One line: "Your normal is the middle of your last 4 weeks of nights: 34–52 ms." (from the data).
3. The glossary's "Good or bad" sentence for the term (meaning text stays in `Glossary`).
4. "Show the numbers", folded: the night's explanation (`ExplanationView`, method and version). For Lowest HR, In bed and Efficiency, whose normal is worked out on read, also the on-read range explanation from `PersonalRange` (method `range28` v1, nights, mean, SD).
While learning: no picture; the graph with its learning words, and "Show the numbers". No reading: as today.

Page charts (`SignalChart` with `compact: false`, line kinds): a point outside its band is a filled dot in its mark colour; inside stays the data colour; a night without a mark (learning, In bed) stays the data colour. The caption "Hollow dots fall outside it." goes. VoiceOver's chart value adds the mark's words for the touched night. Bars don't mark, as today. Body's compact cards keep hollow dots.

`TrendNight` and `TrendPoint` carry the night's `NormalMark?`, built in `BodyModel.nights`: contributors from `ContributorReading.mark`, recovery from `RecoveryStatus.mark`, Lowest HR (and later Efficiency) from the on-read `PersonalRange`.

### Sleep reads (phase 4a)
- No change to `TrendsSnapshot.kinds`, so Body and every other page read nothing more. Instead `observeTrends(endingOn:kinds:)` takes the kinds; the default stays the current list. Only the In bed and Efficiency pages and Sleep's D pass `sleep.inBed` / `sleep.efficiency`.
- `observeSleepStages(endingOn:days:)`: deep, light and REM minutes per night for the window shown, read only by the Sleep page's Stages card.
- `observeSleepTimes(endingOn:days:)`: `night, start_at, end_at` from `sleep_night` for the window shown, read only by the Bedtime page and Sleep's W/M/3M row. Never `uploaded_at` or the JSON columns.
- VeselCore `ClockMedian` (from 18:00, rounded to 5 minutes), shared by `UsualBedtime` (unchanged results, its tests still pass) and new `SleepTimes` (middle bedtime and middle wake, method `sleepTimes` v1, on read, with its explanation).
- Glossary: `timeInBed` ("In bed"), `sleepEfficiency` ("Efficiency"), `bedtime` ("Bedtime and wake") in the Sleep group: what it is, good or bad, what's normal, what affects it, how the band knows.

### New pages (phase 4b)
- `TrendKind.inBed` (bars from 0, minutes drawn in hours, your normal shaded) and `.efficiency` (line, %), each with a normal worked out on read from the 28 nights before it (at least 7), like Lowest HR; not stored; not on Body.
- In bed has **no mark** (a time you choose more than a body signal; a lie-in is not a warning): the band and the value show, no colour, no symbol. Gate item.
- Efficiency counts only low nights, and its normal is drawn from 2 SD under to 1 SD over the mean (its SD is often about 2 points, so ±1 SD would flag ordinary nights): inside ✓; above it light green ↑; under it orange ↓; under 3 SD red ‼. Gate item.
- `PageKind` gains `.inBed`, `.efficiency` (pages through `NightlyDayPart` / `OverTimePart`) and `.bedtime` (no `TrendKind`, like heart rate: its own `BedtimeDayPart` and `BedtimePeriodPart`).
- Bedtime · wake chart: one floating bar per night from bedtime to wake on a clock axis from 18:00 at the top to 12:00 (or to the next whole hour after the latest wake in the window, if later), evening at the top so a later night sits lower; a bedtime before 18:00 sits at 18:00 and its scrub text says the real time. On D that night is full and the others faded. Header on D: "23:20 to 07:08" with the night line; on W, M, 3M a small "Usually" over the middle bedtime and wake ("23:20 to 07:08") with the dates. A finger on a bar reads "Mon 2 Nov · 23:20 to 07:08"; with VoiceOver "Monday 2 November, 23:20 to 07:08". Clock times, never a duration, everywhere bedtime and wake show: the Sleep D and W/M/3M rows ("23:20 to 07:08"), this header, the scrub and VoiceOver; the bars carry no labels of their own (the axis shows clock hours). No band, no mark.
- `-VeselPage inBed|efficiency|bedtime` works through `PageKind(rawValue:)`.

### Sleep page (phase 5)
D, top to bottom: header "7 h 40 m asleep · Last night"; the stages and heart-rate chart card (as today); "The night" card: Bedtime · wake ("23:20 to 07:08", no mark), In bed (value, no mark), Efficiency (value + mark), each row a button opening its page on D; a "Your normal" card with `NormalPicture` for time asleep (from `InRange.sleep`'s `LineScale`), replacing the range line row and the "Your normal" row; the Stages card (Deep, Light, REM, Awake, opening their meanings as today); the Overnight card with HRV, Lowest HR and Breathing showing value + mark and no chevrons. The "Time asleep" card with the second big figure and its MeaningRow goes (the header says it; the title opens its meaning). Why In bed and Efficiency weren't seen: they sat in that third block, below the fold; now they are the first rows under the chart.

W, M, 3M: header and time-asleep bars as today; under the chart a "Stages" card: one stacked bar per night, deep at the bottom, light, REM on top (awake left out), a three-item legend with names, hold-then-drag scrub and a tap opening D; then rows In bed, Efficiency (plain averages) and Bedtime · wake (middle bedtime and wake, "23:20 to 07:08"), no marks, each opening its own page on the same period and window.

The header is shared: `OverTimePart` owns one selection for its chart and one for the slot's chart and passes the slot's binding in. The header shows the finger's reading from whichever chart is touched ("Mon 2 Nov · Deep 1 h 20 m · Light 4 h 10 m · REM 1 h 30 m" from Stages), else the period summary. Starting a scrub on one chart clears the other's, so only one ever shows; lifting restores the summary. `OverTimePart` gets the slot (between its chart and its worked-out card); only Sleep fills it.

### Alternatives ruled out
- A 1–100 recovery number or Polar's "x of 6" in the header: reverses `2026-10-27-no-score-to-chase.md` (owner, settled).
- Orange on either side for every signal: a great HRV night would look like a warning (owner, settled).
- A soft better-green under 3:1: fails the chart-mark contrast rule once used as a dot.
- Marking Body's cards and Today now: out of scope.
- A band for bedtime and wake: two clock times a night crossing midnight; heart rate already has no band.
- New stored metrics for In bed / Efficiency normals: the Lowest HR precedent is on-read.
- Adding the sleep kinds to `TrendsSnapshot.kinds`: every Body and page read would carry five more series it never shows.

## Files

Phase 1 — marks and colours
- `ios/Packages/VeselCore/Sources/VeselCore/Analysis/NormalMark.swift` (new): `NormalMark`, its side, mapping from `RangeVerdict` + better side, symbol name, spoken words.
- `ios/Packages/VeselCore/Sources/VeselCore/Analysis/NormalScale.swift` (new): value + normal → `LineScale` (clamped track).
- `ios/Packages/VeselCore/Sources/VeselCore/Analysis/InRange.swift`: `LineScale`'s track init made usable by `NormalScale` (internal → shared within the module, no behaviour change).
- `ios/Packages/VeselCore/Sources/VeselCore/Analysis/RecoveryContributors.swift`: `Contributor.better`, `ContributorReading.mark` (sleep above = off ↑).
- `ios/Packages/VeselCore/Sources/VeselCore/Analysis/RecoveryStatus.swift`: `mark` (4–6 inside, 3 off ↓, 1–2 far).
- `ios/Packages/VeselCore/Tests/VeselCoreTests/NormalMarkTests.swift` (new): the whole mapping table; `NormalScale` placement and clamping.
- `ios/Vesel/Assets.xcassets/Mark{Inside,Better,Off,Far}.colorset`, `OnMark{Inside,Better,Off,Far}.colorset` (new, 8).
- `ios/Vesel/Theme/Theme.swift`: the eight palette colours.
- `ios/Vesel/Theme/MarkBadge.swift` (new): the chip, `@ScaledMetric` size; takes `NormalMark`; `#Preview` of all marks, light, dark and AX5.
- `docs/design/system.md`: four mark rows in Colours, a "Mark" component, the contrast pairs under Accessibility.

Phase 2 — Recovery page
- `ios/Packages/VeselCore/Sources/VeselCore/Analysis/RecoveryStatus.swift`: `verdict` short words.
- `ios/Packages/VeselCore/Sources/VeselCore/Analysis/RecoverySentence.swift`: delete `make` and the sentence table; add `quietLine`; keep `driver`, `describe`.
- `ios/Packages/VeselCore/Sources/VeselCore/Analysis/Headline.swift`: `noneStoodOut` shared (not private).
- `ios/Packages/VeselCore/Sources/VeselCore/Analysis/RecoveryContributors.swift`: delete `goodSide` and `GoodSide`.
- `ios/Packages/VeselCore/Tests/VeselCoreTests/RecoverySentenceTests.swift`: drop the `make` tests; add `quietLine` for Polar 3, 2, 1 × all inside / one better / all learning; the verdict words.
- `ios/Packages/VeselCore/Tests/VeselCoreTests/RecoveryContributorsTests.swift`: the `goodSide` test (about lines 121–186) moves into `NormalMarkTests` as mark cases, then is deleted here.
- `ios/Vesel/Pages/RecoveryPage.swift`: header words, no range line row.
- `ios/Vesel/Recovery/RecoveryView.swift`: the card as above; worked-out list without "The sentence".
- `ios/Vesel/Recovery/ContributorRow.swift`: name, value, `MarkBadge`; opens the page; no chevron, no meaning sheet.
- `ios/Vesel/Recovery/RecoveryModel.swift`: drop `headline`; expose `quietLine`.
- `ios/Vesel/Body/BodyCard.swift`: recovery y-domain fits; whole-step axis values.
- `ios/Vesel/Body/BodyModel.swift`: recovery `scrubText` and `periodSummary` use `RecoveryStatus.verdict` ("Most nights").
- `docs/how-it-works/recovery.md`, `docs/design/screens.md` (Recovery), `CHANGELOG.md`.

Phase 3 — signal pages
- `ios/Vesel/Theme/NormalPicture.swift` (new): draws a `LineScale` and plain strings; stacked labels at accessibility sizes; previews: inside, better, off, far, past the end, AX5.
- `ios/Vesel/Pages/NightlyDayPart.swift`: the "How it's worked out" card; `NightsChart` caption without the hollow line.
- `ios/Vesel/Pages/OverTimePart.swift`: caption without the hollow line.
- `ios/Vesel/Body/BodyModel.swift`: `TrendNight.mark`, `TrendPoint.mark`, the night's `LineScale`, the on-read range explanation for Lowest HR.
- `ios/Vesel/Body/BodyCard.swift`: `SignalChart` full form fills outside dots in the mark colour; VoiceOver words.
- `ios/Packages/VeselCore/Sources/VeselCore/Analysis/PersonalRange.swift`: `explanation(unit:)` for a range worked out on read (`range28` v1).
- `ios/Packages/VeselCore/Sources/VeselCore/Glossary/Glossary.swift`: lookup of a term's "Good or bad" section (no new text).
- `ios/VeselAppTests/BodyModelTests.swift`: marks per night for a contributor, recovery and Lowest HR.
- `docs/how-it-works/days.md`, `docs/how-it-works/recovery.md` (moving normal), `docs/design/screens.md` (pages), `CHANGELOG.md`.

Phase 4a — sleep reads
- `ios/Packages/VeselStorage/Sources/VeselStorage/Observations.swift`: `observeTrends(endingOn:kinds:)`; `observeSleepStages`; `observeSleepTimes`.
- `ios/Packages/VeselStorage/Tests/VeselStorageTests/TrendsSnapshotTests.swift`: chosen kinds only; stages and sleep times for the window only, never `uploaded_at`.
- `ios/Packages/VeselCore/Sources/VeselCore/Analysis/ClockMedian.swift` (new); `UsualBedtime.swift` uses it.
- `ios/Packages/VeselCore/Sources/VeselCore/Analysis/SleepTimes.swift` (new).
- `ios/Packages/VeselCore/Tests/VeselCoreTests/SleepTimesTests.swift` (new): across midnight, even and odd counts, wake after noon (13:30), bedtime before 18:00; `UsualBedtimeTests` unchanged and green.
- `ios/Packages/VeselCore/Sources/VeselCore/Glossary/Glossary.swift`: three terms, Sleep group; `GlossaryTests.swift`: 24 terms.
- `docs/how-it-works/meanings.md`, `CHANGELOG.md` only if something shows (it doesn't yet).

Phase 4b — new pages
- `ios/Vesel/Body/BodyModel.swift`: `kinds` passed to `observeTrends`; `TrendKind.inBed`, `.efficiency` (title, term, metric kind, colour, bars/line, format, axis, on-read normal, efficiency's 2-under/1-over normal and mark, In bed no mark).
- `ios/Vesel/Pages/SignalPage.swift`: `PageKind` cases, titles, terms; `PeriodPage` routes `.bedtime`.
- `ios/Vesel/Pages/BedtimePage.swift` (new): `BedtimeDayPart`, `BedtimePeriodPart`, the floating-bar chart, its own small model observing `observeSleepTimes`.
- `ios/Packages/VeselCore/Sources/VeselCore/Analysis/NormalMark.swift`: efficiency's mapping; tests in `NormalMarkTests`.
- `ios/VeselAppTests/BodyModelTests.swift`: In bed / Efficiency normals on read, averages, efficiency marks.
- `docs/how-it-works/sleep.md`, `docs/how-it-works/days.md` (page list, `-VeselPage`), `.agents/skills/layers/SKILL.md` (page list, chart exceptions), `CHANGELOG.md`.

Phase 5 — Sleep page
- `ios/Vesel/Pages/SleepPage.swift`: D order; a week `BodyModel` with In bed, Efficiency and Lowest HR kinds for marks.
- `ios/Vesel/Sleep/NightView.swift`: "The night" card, Overnight rows with marks; the Time asleep card goes.
- `ios/Vesel/Pages/OverTimePart.swift`: the slot and the second selection; header rule.
- `ios/Vesel/Sleep/SleepPeriodDetails.swift` (new): the Stages card (stacked bars, its own model on `observeSleepStages`) and the three rows (In bed and Efficiency averages, `SleepTimes` middle).
- `docs/how-it-works/sleep.md`, `docs/design/screens.md` (Sleep), `CHANGELOG.md`.

## Steps

### Phase 1 — marks and colours
- [x] 1. `NormalMark`, `NormalScale`, `ContributorReading.mark`, `RecoveryStatus.mark`, with `NormalMarkTests`.
- [x] 2. Eight colour sets, `Theme.Palette` entries, `MarkBadge` with previews.
- [x] 3. `docs/design/system.md`: colours, component, contrast pairs; layers rule line for marks.

### Phase 2 — Recovery page
- [x] 1. `RecoveryStatus.verdict`, `quietLine`, `noneStoodOut` shared; delete `make` and tests.
- [x] 2. `RecoveryPage` header and order; `RecoveryModel`.
- [x] 3. `RecoveryView` card and `ContributorRow`; delete `goodSide`/`GoodSide`, move their test cases.
- [x] 4. `SignalChart` recovery y-domain and axis; `BodyModel` recovery scrub and W/M/3M header words.
- [ ] 5. Docs and changelog (done); screenshots in the states under Verification (left for the final pass).

### Phase 3 — signal pages
- [x] 1. `TrendNight.mark` / `TrendPoint.mark`, `PersonalRange.explanation`; tests.
- [x] 2. `SignalChart` full form: filled mark-coloured outside dots; VoiceOver words; captions.
- [x] 3. `NormalPicture` with previews.
- [x] 4. `NightlyDayPart` "How it's worked out" card; glossary lookup.
- [ ] 5. Docs and changelog (done); screenshots (left for the final pass).

### Phase 4a — sleep reads
- [x] 1. VeselStorage: `observeTrends(kinds:)`, `observeSleepStages`, `observeSleepTimes`, tests.
- [x] 2. VeselCore: `ClockMedian`, `UsualBedtime` on it, `SleepTimes`, tests.
- [x] 3. Glossary entries and test count.

### Phase 4b — new pages
- [x] 1. `TrendKind.inBed` / `.efficiency`, efficiency mapping; tests.
- [x] 2. `PageKind` cases; In bed and Efficiency through the existing parts.
- [x] 3. `BedtimePage` parts and chart; previews.
- [ ] 4. Docs, layers rule, changelog (done); screenshots with `-VeselPage inBed|efficiency|bedtime -VeselPeriod d|m` (left for the final pass).

### Phase 5 — Sleep page
1. `OverTimePart` slot and shared header; `SleepPeriodDetails`.
2. Sleep D: new order, "The night" card, "Your normal" picture, Overnight rows with marks; the Time asleep card goes.
3. Docs, screens.md, changelog; screenshots of D and M, default and largest text, light and dark.

## Decisions
1. **mine** — Four marks: darker green ✓ inside (no arrow), lighter green + arrow outside on the good side, orange + arrow outside on the side that matters, red ‼ well outside (the existing `wellBelow`/`wellAbove` step). Arrows only outside. Colour never alone. Light and dark tokens meeting `system.md`'s contrast rules; the marks go into `system.md`.
2. **mine** — Today, widgets and the lock screen are out of scope.
3. **mine** — Recovery D header: short words verdict + date line only; Polar's "x of 6" moves into "How it's worked out"; no number chips above the chart.
4. **mine** — Recovery chart's y-scale fits the values shown.
5. **mine** — "What went into it": name, value, mark; no chevrons; no colour key; the whole row opens the signal's own page, not the meaning sheet. Much less text.
6. **mine** — Signal pages' "How it's worked out" leads with a picture: your normal as a band, last night as a dot, values labelled; shorter text after.
7. **mine** — Sleep W, M, 3M: main chart stays time asleep; under it stacked deep/light/REM bars per night, then In bed, Efficiency and Bedtime · wake rows, each opening its own chart page.
8. **mine** — No 1–100 recovery number (reaffirms `2026-10-27-no-score-to-chase.md`).
9. **agent's** — Chart types: line + dots for Recovery, HRV, Resting HR, Lowest HR, Breathing, Skin temperature and Efficiency (a value read against a band night after night); bars from 0 for Time asleep and In bed (durations); stacked bars for stages (parts of one night); floating bars on a clock axis for Bedtime · wake (a span, not an amount).
10. **mine** — The big recovery sentence and its why line go. One muted line stays only when Polar is 3 or lower and every marked row is inside ("Polar weighs them together"), so a low verdict is never left unexplained.
11. **mine** — Header words: 6 "Well recovered", 5 "Good recovery", 4 "Recovery OK", 3 "Lower than usual", 1–2 "Low recovery"; the scrub and W/M/3M ("Most nights · Good recovery") use the same words.
12. **agent's** — The Recovery range line row on D goes; on Sleep D the range line becomes the normal picture. The decision file's Supersedes line now names this.
13. **mine** — Sleep above its normal is orange ↑, never red. Far on the better side stays light green. Breathing and skin temperature have no better side. Lowest HR is better lower; Recovery: 3 orange, 1–2 red.
14. **agent's** — Mark tokens as in Approach: every chip ≥ 3:1 so it also works as a chart dot; every symbol ≥ 4.5:1 on its chip; dark symbols on orange and better-green in light mode.
15. **agent's** — On Recovery, Sleep and the signal pages (not Body's compact cards), chart dots outside the normal are filled in their mark colour instead of hollow; the band position is the second cue; VoiceOver says the words. Bars stay unmarked.
16. **agent's** — The recovery y-scale rule applies to W, M, 3M and Body's Recovery card: it is one chart.
17. **agent's** — In bed and Efficiency get a moving normal worked out on read (like Lowest HR), explained on their pages; nothing new is stored. Bedtime · wake has no band and no mark.
18. **mine** — In bed has no mark; Efficiency counts only low nights, normal from 2 SD under to 1 SD over, red under 3 SD (to stop ordinary nights turning orange). Approved at the gate.
19. **agent's** — Three new pages with D · W · M · 3M and three new glossary entries.
20. **agent's** — Bedtime · wake over a period is the median from 18:00 (one helper shared with the usual bedtime), not a mean that midnight would break.
21. **agent's** — Sleep D: the duplicate "Time asleep" card goes; In bed, Efficiency and Bedtime · wake are the first rows under the chart, then the normal picture.
22. **agent's** — A contributor row opens its page on D for that night (the old "Night by night" opened M).
23. **agent's** — The new sleep series are read only where shown (In bed / Efficiency pages, Sleep D, the Stages card, the Bedtime page), not by every Body read.
24. **agent's** — Six phases, one PR each; 4a and 4b before 5 so the Sleep rows have pages to open.
25. **mine** — Signal pages' D: the band-and-dot picture moves to the top under the header, then a line graph of the nights ("a line graph is actually really good"), then "How it's worked out" with the shorter text and "Show the numbers".
26. **mine** — Bedtime · wake shows clock times ("23:00 to 07:08"), never a duration: Sleep's rows, the Bedtime page header and the finger-read. Assumption (agent's): this also covers VoiceOver and the W/M/3M "Usually" header; the bars carry no labels of their own, the axis shows clock hours.
27. **mine** — Gate answers as recommended: the header words (11), the sentence goes with the one quiet line (10), much longer sleep orange ↑ never red (13), In bed no colour and Efficiency flags only clearly low nights (18), the two greens checked on the phone in daylight after the build (Verification).
28. **mine** — Sleep is "a bit noisy" but OK for now; build it as planned and iterate on Sleep later.

## Deviations
- Run 1: only iOS 27.0 simulators exist on this machine, so app builds target the iOS 27.0 iPhone simulator, not the contract's iOS 26.5 one.
- Run 2: `TrendsSnapshot.kinds` gained `MetricKind.steps`, skipped by the metric loop and read only when requested (default behaviour unchanged). New plain VeselCore types `SleepNightTimes` and `NightStages`; `ClockMedian` is public. The wording of the three new glossary terms is the agent's own.
- Phase 4b: Efficiency's on-read normal has its own method name and wording, `range28Low` version 1 (`PersonalRange.lowNightsExplanation`), because `range28`'s text says "mean ± 1 standard deviation", which is not what Efficiency draws. `NormalMark(efficiency:range:)` and `PersonalRange.lowNightsNormal` live in VeselCore beside the other marks.
- Phase 4b: `NormalPicture` and `NightPicture` take an optional mark (nil: the data colour, no badge) instead of a second view, for In bed's page.
- Phase 4b: `TrendKind.readKinds` says what a thing's own pages read (In bed and Efficiency only their series, the others Body's list); `BodyModel` takes it as `kinds`. `trendAxes` gained an optional `yLabel` so the Bedtime chart's axis reads clock hours.

## Verification
- Every phase: the contract's fast checks, then the full checks before the PR (`solidvibes lint .`, `swift test` for VeselCore, VeselStorage, VeselSync, VeselBackupKit, the app's `xcodebuild test` on iPhone 17 Pro Max iOS 26.5, the Mac build, `uv run pytest`).
- Phase 1: `NormalMarkTests` cover every verdict × better side, sleep above, recovery 1–6, learning, `NormalScale` clamping. Contrast pairs recomputed from the hex values in the PR body. `MarkBadge` previews light, dark and AX5.
- Phase 2: `-VeselScenario normal -VeselPage recovery` on D and M; also a low night and `-VeselScenario firstDay`. Check: no "of 6" in the header; marks, no chevrons; tapping HRV opens HRV on D for that night; the scale no longer starts at 1; VoiceOver "HRV, 62 ms, above your normal, the good side"; M header "Most nights · Good recovery".
- Phase 3: `-VeselPage hrv|restingHeartRate|lowestHeartRate|breathing|skinTemperature` on D and M: the card leads with the picture; outside dots coloured; "Show the numbers" has method and version (and `range28` for Lowest HR). US units for skin temperature. AX5 text size.
- Phase 4a: storage and core tests; `UsualBedtimeTests` unchanged.
- Phase 4b: `-VeselPage inBed|efficiency|bedtime` with `-VeselPeriod d|w|m|3m`; a week crossing a daylight-saving change for bedtime.
- Phase 5: `-VeselPage sleep -VeselPeriod d` and `m`, light and dark, default and largest text: In bed and Efficiency are visible without scrolling at default text size; the Stages scrub fills the header and clears the other chart's; a tap opens D.
- Owner only, after the build: both greens (inside vs good side) and the orange on the real iPhone in daylight.

## Rule gaps
- Marks and scales (layers rule, when phase 1 lands): "A mark against your normal comes from `NormalMark`, and where a band and dot sit from `NormalScale` or `InRange` (VeselCore); views draw `MarkBadge` and `LineScale` and never place or colour them themselves."
- Chart exceptions (layers rule, when phases 4b and 5 land): "Every signal over weeks is `SignalChart`" gains two stated exceptions: Sleep's Stages card on W, M, 3M (a second chart on the Sleep page: stages are parts of each night's time asleep, not a value with a normal, so it has no band; it scrubs into the same header) and the Bedtime · wake chart (two clock times a night, no band, like heart rate's `HeartRateDaysPart`).
- Page list in the layers rule and `days.md` gains In bed, Efficiency and Bedtime · wake (phase 4b).
- `system.md`'s "Colour never alone: … changes have an arrow" becomes "a mark has its symbol" (phase 1).
