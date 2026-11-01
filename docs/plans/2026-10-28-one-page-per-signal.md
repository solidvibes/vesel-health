---
status: implemented
---

# One page per signal (D · W · M · 3M)
**Date**: 2026-10-28
**Status**: Implemented 2026-10-28
**Touches**: `docs/how-it-works/days.md`, `docs/how-it-works/recovery.md`, `docs/how-it-works/sleep.md`, `docs/how-it-works/stress.md`, `docs/design/screens.md`, `.agents/skills/layers/SKILL.md`, `docs/decisions/2026-10-28-today-journal-body.md`

## TL;DR
- One page per thing: Recovery, Sleep, Stress, Heart rate, Steps, HRV, Resting HR, Lowest HR, Breathing, Skin temperature.
- Like Apple Health: one chart at the top, a D · W · M · 3M switch, a header above the chart.
- Header: D = the day's number and its date; W/M/3M = "average a day/night" and the date range.
- Scrubbing replaces the header with the touched bar's value and time/date; lifting restores it.
- ‹ › and a swipe on the chart move one period; tapping a day in W/M/3M opens D on it.
- Moving normal band stays behind W/M/3M (the existing `SignalChart`).
- Below the chart on D: the day's existing cards (range line, stages rows, What helps, How it's worked out…).
- Today/Journal open D for their day; Body opens on its current range (M by default).
- `SignalChartView`, `LastWeeksCard`, `SignalChartRoute`, `.chart`/`.contributor` routes: deleted.
- `PageRoute` becomes one struct: kind, day, period.
- Recovery and the overnight signals: D shows the 7 nights ending on that night, that night highlighted.
- Sleep D chart = stages + overnight heart rate; Stress D = hourly bars; Heart rate D = 5-min line; Steps D = hourly bars.
- Heart rate W/M/3M: a lowest–highest bar per day, worked out on read; no band.
- Body loses its own 4 weeks / 3 months switch: cards always show 4 weeks, open the page on M (decision 18).
- Today's Recovery / Sleep / Stress rows get bigger names and values (decision 19).
- Every chart in the app is either on a page (D·W·M·3M) or a glance that opens one (Chart inventory).
- No migration, no new table. Three coder runs.

## Context
The same thing opened two pages: a day page from Today/Journal (ending with a "Last 4 weeks" card) and a separate weeks/months chart page from Body (`SignalChartView`). The owner decided one page per thing, shaped like Apple Health's Steps page: one chart, a D · W · M · 3M switch, a header that the finger replaces, period paging. This supersedes the "Body: weeks and months only, a separate view" part of `docs/decisions/2026-10-28-today-journal-body.md` and the earlier stacked "day on top / Over time below" idea (`onepage.html`), which is dropped.

Builds on branch `fix/steps-bars` (Date-based `HourlyStepsChart` with scrub, Today Steps card with bars). Start from that branch's tip once its commit has landed.

## Constraints
- Rules: `AGENTS.md` (non-negotiables, Factory `layers`), `.agents/skills/layers/SKILL.md`, `.agents/skills/testing/SKILL.md`, `.agents/skills/data/SKILL.md` (reads only; nothing leaves the phone).
- Packs: none listed in `docs/stack.md` (blank 0.1.0).
- Layers: screen (SwiftUI) → view model → VeselStorage (GRDB `ValueObservation`) / VeselCore. Pure window/period math lives in VeselCore with tests. `ios/Vesel/Theme/` views take plain values only (compiled into the widget target).
- A page gets its day in its route and never reads `AppEnvironment.days.day`. The ‹ clamp reads only `environment.days.firstDay` (the first day with data, nil while unknown → ‹ stays enabled), never the shared selected day.
- `ios/Vesel/Theme/` is compiled into the widget and widget-test targets (`ios/project.yml`): anything new there (the gesture modifier) uses SwiftUI/UIKit and plain values only, no `AppEnvironment`, no `PageRoute`.
- No score to chase (`2026-10-27-no-score-to-chase.md`): averages are plain; no arrows, no best, no streak, no "vs last week".
- Range lines (`2026-10-28-range-lines.md`): Recovery/Sleep/Stress pages keep their range line (as the first card under the chart on D).
- Risk areas: none touched (no migration, no data leaves the phone, no deletes).
- VoiceOver and the largest Dynamic Type on every new piece; DST-correct (all day math through `DayKey`, `DayBuckets`, wall-clock `Date`s in the zone).
- Delete dead code; no shims.

## Approach
One generic page, `SignalPage(kind:day:period:)`, replaces the five day pages' frames and `SignalChartView`:

```
Title (TermTitle, opens meaning)
[ D | W | M | 3M ]                       segmented
‹  HEADER: big value                ›    scrub replaces it
   date / date range (muted)
CHART (D: the day's chart; W/M/3M: SignalChart over the band)
caption (W/M/3M: shading + learning note)
— D only — the day's cards
— W/M/3M — "How it's worked out" for the latest day in range
```

- **State** (`SignalPageModel`, @Observable, app target): `period`, `day` (D's day), `end` (W/M/3M window end). Window maths in VeselCore `PeriodWindow` (pure, tested): windows are rolling and end on today, today − n, today − 2n… (n = 7, 28, 90); switching from D to a period picks the window holding `day`; ‹ › moves `day` by one day on D, `end` by n on W/M/3M; › is disabled at today; ‹ is disabled once the earlier window would end before the first day with data (`DaySelection.firstDay`); tapping a day sets `day` and `period = .day`; switching back to D keeps `day`.
- **D part**: each kind keeps its existing day model, re-created per day with `.id(day)` (as pages do now). Each D part builds the header (value + date line) and the chart, and passes the chart a `selection` binding so the header can show the scrub text. Its cards below are the existing page content minus the chart that moved up and minus `LastWeeksCard`.
- **W/M/3M part** (`OverTimePart`): `BodyModel(ranges: [range], endingOn: end)` re-created per `end` with `.id`. `SignalChart` gains `selection`, `highlighted: DayKey?` and `onPickDay`. Header = `BodyModel.periodSummary(kind)`. Caption and "How it's worked out" move from `SignalChartView`.
- **Gestures** (one modifier in `Theme/ChartScrub.swift`, replacing `chartScrub` on these charts): press-and-hold (~0.25 s) then drag = scrub; a quick horizontal swipe = previous/next period; a tap on W/M/3M = pick that day. Hold-to-scrub is what lets the swipe work (Apple Health does the same). Three neighbours must keep working, and each is a verification check:
  - **The page's vertical scroll.** A plain `.gesture(DragGesture())` on a chart inside a `ScrollView` swallows a scroll that starts on the chart. Use `.simultaneousGesture` and act only when the drag is mostly horizontal (`abs(dx) > abs(dy) * 1.5`, ≥ 40 pt), the pattern `Days/WeekStrip.swift` already uses; the hold-then-drag is a `LongPressGesture(minimumDuration: 0.25).sequenced(before: DragGesture(minimumDistance: 0))`. No `chartXSelection` on these charts (it claims the touch at once and kills the swipe).
  - **Back navigation.** iOS 26 (the deployment target) lets a right swipe anywhere in a pushed page go back, not only from the edge. A right swipe on the chart must page to the earlier period, and a right swipe anywhere else (or from the screen edge) must still go back. If SwiftUI cannot make the chart's swipe win over the system back swipe, fall back to a `UIGestureRecognizerRepresentable` pan on the chart that the navigation controller's content pop recognizer is set to require to fail; if that also fails, drop the chart swipe (‹ › stay) and say so in the PR — owner decision 15.
  - **Charts shared with glances.** `ReadingLineChart` (Theme) and `SleepStagesChart` also draw Today's and Journal's glances. They take the gesture as a parameter (`scrub: ChartScrubStyle = .immediate | .holdThenDrag(onSwipe:onTap:)` or equivalent); glances and any other caller keep today's `chartScrub`. VoiceOver: the chart stays one adjustable element (steps: 1 h on hourly bars, 15 min on lines and stages, 1 day on W/M/3M), plus a "Show this day" action on W/M/3M while a day is selected; ‹ › are real buttons ("Earlier day", "Later week", "Earlier 4 weeks"…).
- **Heart rate W/M/3M**: new `HeartRateDaysModel` reads `observeHeartRatePeriods(endingOn: end, days: n)` and groups with `DailyHeartRate.days` off the main thread (as `ReadingDayModel` does); drawn as a lowest–highest bar per day with the day's average as a dot, scrubbable and tappable like the rest.

Ruled out: the stacked "day on top, Over time below" page (owner replaced it); keeping the chart page behind a link (that is the smell being removed); a second over-time chart type for nightly measures (reuse `SignalChart`).

## Decisions
1. **mine** — One page per thing; Today, Journal and Body open the same page; `SignalChartView` and the chart route are deleted.
2. **mine** — Apple Health shape: one chart, D · W · M · 3M, header (D: the day's number + date; W/M/3M: plain "average a day" + date range), scrub replaces the header, swipe or ‹ › moves a period, moving normal band behind W/M/3M, tapping a day in W/M opens D on it, D shows the day's existing cards below; Today/Journal open on D, Body on M.
3. **mine** — Overnight signals (HRV, resting HR, lowest HR, breathing, skin temperature) get the same page.
4. **agent's** — Periods are rolling windows ending on today: W = 7 days, M = 4 weeks (28 days), 3M = 90 days; ‹ › moves by that many days. Why: same windows as Body and the 4-week normal; no calendar edge cases.
5. **agent's** — 3M keeps one point per day, as Body's charts do today. Why: the band follows each night's own normal; weekly buckets would blur it.
6. **agent's** — Marks stay as Body draws them: bars for Stress and Steps, a line with dots for the nightly measures. Why: reuse `SignalChart`; a nightly measure is a level, not an amount.
7. **mine** (owner approved 2026-10-28) — D for one-value-per-night things (Recovery, HRV, resting HR, lowest HR, breathing, skin temperature): the 7 nights ending on that night, that night drawn full and the others faded; header is that night's value. Why: nothing finer than one value per night is stored, and the week gives the night its context.
8. **agent's** — Sleep D chart = the stages with the overnight heart-rate line (moved up from the stages card). Stress D = hourly stress bars (now scrubbable). Heart rate D = the day's 5-minute line. Steps D = hourly bars. Why: each is the day's own picture already on its page.
9. **agent's** — Heart rate W/M/3M: a bar per day from the lowest to the highest 5-minute average (dot at the day's average), worked out on read; no band (no daily normal exists); header = the range over the shown days ("48–131 bpm") with its date range, on D the day's range. Why: matches the Journal card and Apple Health; resting HR already has its own page.
10. **mine** (owner approved 2026-10-28) — Recovery W/M/3M header = the most frequent verdict ("Mostly OK", ties go to the newer night), not an average. Why: an average of Polar's words means nothing. Not a score: no number, no count of good nights ("OK or better on 22 of 28" would be one to chase), no comparison with the previous period; the scrub shows each night's own word.
11. **agent's** — Averages count only days with a number; Steps leaves today out of its average (the day isn't over). Sleep/overnight say "a night", Stress/Steps "a day".
12. **agent's** — Body opens the page on M (with decision 18; if the owner keeps Body's switch, on Body's current range). Why: the chart the owner just looked at stays the same.
13. **agent's** — From a day context, overnight links open D for that night (Sleep's Overnight rows). A contributor's "Night by night" opens that signal on M. Why: the label promises nights.
14. **agent's** — Tapping a day works on 3M too. Why: one rule for every period.
15. **mine** (owner approved 2026-10-28) — Scrub needs a short hold before the finger moves; a quick swipe pages. Why: both on one chart. Cost: scrubbing is a touch slower than today's instant scrub; if the chart swipe cannot coexist with iOS 26's swipe-back, ‹ › alone move the period.
16. **agent's** — No Heart rate card on Body. Why: unasked; Body already has resting and lowest heart rate.
17. **agent's** — Launch flags: `-VeselNightChart`, `-VeselTrendChart`, `-VeselContributor` and (with 18) `-VeselTrendRange` go; `-VeselPage` takes every kind and pushes on the launch tab (Body included); new `-VeselPeriod d|w|m|3m`. Why: one page, one flag.
18. **mine** (owner approved 2026-10-28) — Body drops its own 4 weeks / 3 months menu: every Body card always shows the last 4 weeks and opens the page on M; the period switch lives only on the page. `TrendRange` is deleted and replaced by VeselCore's `PagePeriod` (BodyModel takes one `PagePeriod`). Why: one switch in one place; Body is the overview, the page is where you look closer. Cost: a 3-month look at everything is one tap per signal instead of one switch for all. If the owner keeps Body's switch, Body's menu must list only 4 weeks and 3 months (never the new week).
19. **mine** — Today's Recovery / Sleep / Stress rows are the main thing to read on Today: their name and value go from `Theme.Typography.label` (subheadline semibold) to `Theme.Typography.heading` (title3 semibold), in `LineRow` and `FirstWeekRow` alike so the three rows match. `LineRow` also draws the range line under the chart on the Recovery/Sleep/Stress D pages; it changes there too (one row style, no variant). Not in the widget target (`Today/` is app-only). Checked at the largest accessibility size, where the row already stacks name over value.
21. **mine** — Haptics: a light selection tick (`.sensoryFeedback(.selection, trigger:)`) each time the scrub moves onto a new bar, hour or point; the same tick when the period changes (D/W/M/3M switch, swipe or ‹ ›) and when a tap on a day opens D. No haptic while the finger stays on one bar; none on glances. Why: the owner asked to feel the scrub and every state change.
20. **mine** — Every chart follows D · W · M · 3M: it is on a page, or it is a glance that opens a page on D, or it is exempt for a stated reason (Chart inventory below).

### Chart inventory (decision 20)

| Chart (file) | Where | Becomes |
|---|---|---|
| `SignalChart` (`Body/BodyCard.swift`) | Body cards | Glance; opens the signal's page on M. Also the page's W/M/3M chart. |
| `SignalChart` in `SignalChartView` / `LastWeeksCard` | chart page, pages' last card | Deleted. |
| `HourlyStepsChart` (`Steps/`) | Steps page | Steps D chart. |
| `HourlyStepsGlance` (`Steps/HourlyStepsChart.swift`) | Today Steps card, Journal | Glance; opens Steps on D. |
| `HourlyStressChart` full (`Stress/`) | Stress page | Stress D chart. |
| `HourlyStressChart` compact | Journal | Glance; opens Stress on D. |
| `ReadingDayChart` → `ReadingLineChart` (`Pages/ReadingDay.swift`, `Theme/`) | Heart rate page | Heart rate D chart. |
| `ReadingLineChart` | Today Heart rate card, Journal | Glance; opens Heart rate on D. |
| `SleepStagesChart` + overnight `ReadingLineChart` (`Sleep/NightView.swift`) | Sleep page | Sleep D chart (`SleepNightChart`). |
| `SleepStagesChart` compact | Journal | Glance; opens Sleep on D. |
| `HeartRateDays` range bars (new) | Heart rate page | Heart rate W/M/3M chart. |
| Nightly 7-night chart (`NightlyDayPart`, new) | Recovery and overnight pages | Their D chart. |
| `FitnessScale` (`Body/`) | Heart fitness | Exempt: one monthly estimate shown as a band, not a series per day (`2026-10-27-no-score-to-chase.md`). |
| `RangeLine`, `RangeArc`, `DayDots`, stress ring | Today rows, widgets, week strip, calendar | Exempt: one value against its normal, or a day picker; not a chart over time. They open (or are) the D page / day already. |
| Widgets (`ios/VeselWidgets`) | Home / Lock Screen | Exempt: no charts; a tap opens Today with the page on D via `vesel://` URLs. |
| About you | Body | No chart. |

### New decision file (coder creates `docs/decisions/2026-10-28-one-page-per-signal.md`)

```markdown
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
```

## Files
Create:
- `ios/Packages/VeselCore/Sources/VeselCore/Analysis/PeriodWindow.swift` — `PagePeriod` days (1/7/28/90), window end holding a day, paging, clamps; most-frequent recovery word; plain average.
- `ios/Packages/VeselCore/Tests/VeselCoreTests/PeriodWindowTests.swift` — windows, paging, clamps, DST weeks (EU 25 Oct 2026, US 1 Nov 2026), tie rule.
- `ios/Vesel/Pages/SignalPage.swift` — `PageKind`, `SignalPage` frame, `SignalPageModel`, period picker, `PageHeader` (value, date line, ‹ ›, scrub override).
- `ios/Vesel/Pages/OverTimePart.swift` — W/M/3M: `BodyModel` per window, `SignalChart`, caption, How it's worked out (moved from `SignalChartView`).
- `ios/Vesel/Pages/NightlyDayPart.swift` — D for Recovery's chart and the overnight signals: 7 nights, highlighted night, the night's normal + How it's worked out cards.
- `ios/Vesel/Pages/HeartRateDays.swift` — `HeartRateDaysModel` + range-bar chart for heart rate W/M/3M.

Modify:
- `ios/Vesel/Pages/PageRoute.swift` — `struct PageRoute { kind: PageKind; day: DayKey; period: PagePeriod }`; one destination (`SignalPage`); drop `.chart`, `.contributor`.
- `ios/Vesel/Pages/RecoveryPage.swift`, `SleepPage.swift`, `CalmPage.swift`, `HeartRatePage.swift`, `StepsPage.swift` — become D parts (`RecoveryDay`, `SleepDay`, `StressDay`, `HeartRateDay`, `StepsDay`): header + chart + cards; no frame, no `LastWeeksCard`.
- `ios/Vesel/Pages/PageScreen.swift` — keep only what `SignalPage` still uses (`PageTitle`, `PageDayLine`); delete the rest.
- `ios/Vesel/Pages/ReadingDay.swift` — `ReadingDayChart` takes a `selection` binding, drops its `ScrubLabel`.
- `ios/Vesel/Body/SignalChartView.swift` — delete the file (`SignalChartView`, `SignalChartRoute`, `LastWeeksCard`).
- `ios/Vesel/Body/BodyCard.swift` — `SignalChart`: `selection`, `highlighted`, `onPickDay`, a 7-day domain; gestures.
- `ios/Vesel/Body/BodyModel.swift` — `TrendRange` deleted; `BodyModel(environment:, period: PagePeriod, endingOn:)` with one period (Body passes `.month`); ticks for the week (every day, short weekday); `periodSummary(kind)`; `TrendKind` → `PageKind` mapping. `observeDayLines` reads only the one period. (If the owner keeps Body's switch, keep `TrendRange` with only `.month`/`.quarter` and map it to `PagePeriod`; never add `.week` to Body's menu.)
- `ios/Vesel/Body/BodyView.swift` — range menu removed (decision 18); cards push `PageRoute(kind:, day: today, period: .month)`; spoken hint "opens the chart" → "opens \(kind.title)".
- `ios/Vesel/Sleep/NightView.swift` — stages+HR chart split out as `SleepNightChart` (selection binding in, scrub text out); Overnight rows open `PageRoute(kind, night, .day)`.
- `ios/Vesel/Sleep/SleepStagesChart.swift` — new gesture modifier instead of `chartScrub`.
- `ios/Vesel/Stress/HourlyStressChart.swift` — full form takes `selection` (1-hour steps); compact unchanged.
- `ios/Vesel/Steps/HourlyStepsChart.swift` — takes `selection` binding, drops its `ScrubLabel`; keeps `HourlyStepsGlance`.
- `ios/Vesel/Recovery/RecoveryView.swift`, `ContributorRow.swift` — `openContributor: (Contributor, DayKey) -> Void` stays; the Recovery D part passes `{ openPage(PageRoute(kind: PageKind(TrendKind($0)), day: $1, period: .month)) }`.
- `ios/Vesel/Theme/ReadingLineChart.swift` — takes the scrub style (immediate for Today/Journal/Sleep glances, hold-then-drag on page D charts) instead of always `.chartScrub`.
- `ios/Vesel/Pages/StepsPage.swift` — `StepsThroughTheDayCard` loses its chart (moved up); file becomes `StepsDay`.
- `ios/Vesel/Today/LineRows.swift`, `ios/Vesel/Today/FirstWeekRows.swift` — name and value in `Theme.Typography.heading` (decision 19).
- `ios/Vesel/Today/HeartRateCard.swift`, `ios/Vesel/Today/StepsCard.swift`, `ios/Vesel/Journal/JournalView.swift` — glances unchanged; their taps open the new route on D.
- `ios/Vesel/Theme/ChartScrub.swift` — `periodChartGestures(selection:onTap:onSwipe:)` (hold-to-scrub, swipe, tap); delete `chartScrub`/`ScrubLabel` if unused after.
- `ios/Vesel/Today/TodayView.swift`, `ios/Vesel/Journal/JournalView.swift` — `openPage(PageRoute(kind:, day:))`.
- `ios/Vesel/RootView.swift`, `ios/Vesel/AppEnvironment.swift` — widget URLs and launch routes build the new route; drop `nightChart`, `trendChart`, `contributor`, `LaunchPage`; add `-VeselPeriod`; Body tab honours `-VeselPage`.
- `ios/Vesel.xcodeproj` — regenerated by `xcodegen generate` (never hand-edited).
- Docs: see "Docs to update".

## Steps

Each run ends compiling, with the fast checks green and a Simulator build. `PageRoute` becomes a struct in Run 1, so every caller moves in Run 1 too (an enum case left behind does not compile).

### Run 1 — core, gestures, the route and the frame (every caller moved, chart page deleted)
- [x] 1. VeselCore `PeriodWindow` + `PagePeriod` + tests (window end holding a day, paging ±1 period, › clamp at today, ‹ clamp at first data day, DST weeks, most-frequent word with newest-wins tie, average of present values). `swift test --package-path ios/Packages/VeselCore`.
- [x] 2. `ChartScrub.swift`: `periodChartGestures` (hold 0.25 s then drag → selection; `simultaneousGesture` horizontal swipe ≥ 40 pt and `abs(dx) > abs(dy) * 1.5` → `onSwipe(±1)`; tap → `onTap(date)`); VoiceOver stays on `scrubAccessibility` with a `step`. `ReadingLineChart` and `SleepStagesChart` take the scrub style. `SignalChart`: selection + `ScrubRule`, `highlighted` (others at 0.35 opacity), `onPickDay` (date → `DayKey` in the zone), week domain/ticks.
- [x] 3. `PageKind`, `PageRoute` struct, `SignalPageModel`, `SignalPage` with picker, `PageHeader`, `OverTimePart` (moves caption, settling note and How it's worked out out of `SignalChartView`), `BodyModel` on one `PagePeriod` + `periodSummary`, `TrendRange` gone. For now each kind's D part is its existing page content without its frame and without `LastWeeksCard`, under a plain header (the day's value + date line) and no chart moved up yet.
- [x] 4. Every caller on the new route: `TodayView`, `JournalView`, `NightView` Overnight rows, Recovery's contributor rows, `BodyView` (range menu removed), `AppEnvironment.open(_ url:)` widget URLs, `LaunchOptions`/`RootView` (`-VeselPage` for every kind on any tab incl. Body, `-VeselPeriod`; `LaunchPage`, `-VeselNightChart`, `-VeselTrendChart`, `-VeselContributor`, `-VeselTrendRange` gone). Delete `SignalChartView.swift` (`SignalChartView`, `SignalChartRoute`, `LastWeeksCard`) and unused `PageScreen` parts. Haptics (decision 21) wired in `periodChartGestures`/the scrub and the period picker. Fast checks + Simulator build. Commit.

### Run 2 — D charts with scrub-to-header: Steps, Heart rate, Recovery, overnight signals
- [x] 5. `StepsDay` (header total, "so far · read 14:32" today; hourly chart up top; caption card), `HeartRateDay` (header day range; 5-min line; Now card today, Lowest/Highest/Average, How it's worked out), `RecoveryDay` (header verdict "Good · 5 of 6"; 7-night chart via `NightlyDayPart`; range line, `RecoveryView`, What helps), overnight kinds via `NightlyDayPart` (header value; normal row; How it's worked out).
- [x] 6. `HeartRateDays` for heart rate W/M/3M. Fast checks + Simulator build. Commit.

### Run 3 — Sleep, Stress, Today's rows, sweep, docs
- [x] 7. Sleep: split `SleepNightChart` out of `NightView` (selection in, "03:12 · Deep · 51 bpm" out to the header); `SleepDay` header "7 h 40 m asleep" + night line; cards: range line, summary, stage rows, Overnight rows → D pages, What helps. Paging D on Sleep moves the day, and a day with no night shows the existing empty state (never the previous night again: `shownNight` only falls back for today).
- [x] 8. Stress: `HourlyStressChart` scrubbable ("14:00–15:00 · High, 72"); `StressDay` header ("45 m high stress", today "8 m so far"); cards: range line, `CalmHeadline`, `CalmWorkedOut`, What helps; learning state keeps `CalmLearning`.
- [x] 9. Today's rows bigger (decision 19): `LineRow` and `FirstWeekRow` name and value → `Theme.Typography.heading`. Screenshot Today at default and at the largest accessibility size.
- [x] 10. Sweep: delete `ScrubLabel`/`chartScrub` only if nothing uses them (Today's and Journal's glances still do). `rg "SignalChartView|LastWeeksCard|SignalChartRoute|TrendRange|\.chart\(|VeselNightChart|VeselTrendChart|VeselContributor|VeselTrendRange"` returns nothing in code or docs (except dated plans/decisions).
- [x] 11. Docs (below), CHANGELOG, new decision file, supersede notes. Full checks, screenshots. Commit.


## Verification
- Fast (contract): `solidvibes lint . && swift test --package-path ios/Packages/VeselCore && swift test --package-path ios/Packages/VeselStorage && swift test --package-path ios/Packages/VeselSync && swift test --package-path mac/Packages/VeselBackupKit`.
- Full (end of Run 3; Runs 1 and 2 end on the fast checks + a Simulator build): the contract's full check (includes `xcodegen generate` and the app `xcodebuild test`).
- Screenshots in a fresh Simulator (`xcrun simctl erase`, then the contract `run` with `-VeselScenario normal`), one per row, each in light; D and W also at the largest accessibility text size:
  - Today → each of Recovery, Sleep, Stress, Heart rate, Steps on D (`-VeselTab today -VeselPage <kind>`), and on W, M, 3M (`-VeselPeriod w|m|3m`).
  - Journal past day → each of the five on D (`-VeselTab journal -VeselDay <date> -VeselPage <kind>`).
  - Body → each of the ten kinds on M (`-VeselTab body -VeselPage <kind> -VeselPeriod m`) and one on 3M.
  - Scrub: `-VeselScrub 14:00` on Steps, Stress, Heart rate D; `-VeselScrub 03:12` on Sleep D — header shows the scrub text.
- Gestures, by hand in the Simulator: a vertical scroll that starts on the chart scrolls the page; a right swipe from the screen edge and a right swipe below the chart go back; a right swipe on the chart pages earlier (or, per decision 15's fallback, the PR says the chart swipe was dropped); Today's and Journal's glances still scrub instantly and still open their page on tap.
- By hand in the Simulator: ‹ › and swipe move one period; › disabled at today; tap a day on W → D for that day; hold-and-drag scrubs, lift restores the header; switching D ↔ W keeps the day; back returns to Today/Journal/Body.
- VoiceOver (Accessibility Inspector): picker segments named "Day, Week, 4 weeks, 3 months"; ‹ › named; chart adjustable; "Show this day" action on W/M/3M.
- DST: unit tests cover weeks crossing 25 Oct (Europe) and 1 Nov 2026 (US); a D page on 25 Oct shows 25 hourly slots correctly (existing hourly tests).
- Heart rate 3M opens in under about a second on the Simulator scenario; if not, note it in the PR. Owner-only: the same on the iPhone with real months of 24/7 samples (the read groups every `hr_sample` row of 90 days by 5 minutes; `ts` is the primary key so it is a range scan, but it re-runs on every sync write while the page is open).
- Today: the Recovery / Sleep / Stress rows in the bigger type, at default and the largest accessibility size; the widgets look unchanged.
- Body: no range menu; every card shows 4 weeks and opens its page on M.
- No score: no arrow, best, streak or comparison text anywhere (`rg -i "best|streak|vs last"` on the new files).
- Owner-only: the real band data on the iPhone.

## Docs to update
- `docs/decisions/2026-10-28-one-page-per-signal.md` — new (content above).
- `docs/decisions/2026-10-28-today-journal-body.md` — add "**Superseded in part by:** 2026-10-28-one-page-per-signal.md (Body's separate chart page)".
- `docs/decisions/2026-10-28-hourly-steps.md` — same note for "Body's Steps card still opens the chart".
- `docs/how-it-works/days.md` — Steps page section → the one page (D/W/M/3M, header, scrub, paging, averages exclude today for steps); pages section; status line `Planned` until `go` lands it.
- `docs/how-it-works/recovery.md`, `sleep.md`, `stress.md` — replace the chart-page and "Last 4 weeks" lines; drop `-VeselNightChart`/`-VeselContributor`; add `-VeselPage`/`-VeselPeriod`.
- `docs/design/screens.md` — Map (`Pages --> Chart` goes; Body → pages), "The pages" rewritten for the new shape, Steps page and Body chart page paragraphs replaced.
- `CHANGELOG.md` under `## Unreleased`: "Each thing now has one page with Day, Week, Month and 3-month views, the same from Today, Journal and Body."

## Rule gaps
All four applied: `.agents/skills/layers/SKILL.md` carries them (Run 1).
- `.agents/skills/layers/SKILL.md`: "every signal over weeks is `SignalChartView` (Body)" → "every signal over weeks is `SignalChart` inside the thing's page (`SignalPage`), with the moving normal band; never a second page". Apply when the code lands.
- `layers`: `PageRoute` is `(kind, day, period)`; a page's period window maths come from `PeriodWindow` (VeselCore). Apply when the code lands.
- Gesture rule: page charts scrub after a short hold so a swipe can page; one modifier in `ChartScrub.swift`; the swipe is a `simultaneousGesture` that acts only when mostly horizontal, so the page still scrolls and iOS 26's swipe-back still works off the chart; glances keep the instant scrub. Apply when the code lands.
- Every chart is on a thing's page or is a glance that opens it (decision 20); a new chart says which. Apply when the code lands.

## Deviations
- Run 1: the Run 1 steps 2 and 3's `periodChartGestures(selection:onTap:onSwipe:)` is `chartScrub(_:style: .holdThenDrag(slot:onSwipe:onTap:))` (`ChartScrubStyle`, default `.immediate`) in `Theme/ChartScrub.swift`, so `ReadingLineChart`, `SleepStagesChart` and `SignalChart` take one `scrub` style instead of a second modifier. The modifier also ticks (`.sensoryFeedback(.selection)`) when the finger moves to another `slot`, and not on lifting.
- Run 1: the Stress D part is `CalmDay` (in `CalmPage.swift`), not `StressDay`: `VeselCore.StressDay` already exists.
- Run 1: Heart rate offers only D until Run 2 adds `HeartRateDays` (`PageKind.periods` hides the picker; delete that property's special case in Run 2). `PageKind.heartRate.trend` is nil.
- Run 1: the overnight kinds' D (`NightlyDayPart`) already exists as header + "Your normal" row + How it's worked out, without the 7-night chart (Run 2 adds it). Recovery's D has no chart yet either.
- Run 1: the page title's meaning sheet (`yours`, explanations) is filled in by the shown part through `SignalPageModel.meaning` (set by `OverTimePart` and `HeartRateDay`), so the title stays one `TermTitle` in the frame; the other D parts leave it empty, as their pages did.
- Run 1: `StepsTotalCard` is gone: the header carries the total and "so far · read 14:32". `PageTitle` and `PageScreen` are gone; the file is now `PageDayLine.swift`.
- Run 1: the hold-then-drag scrub selects once the finger moves after the 0.25 s hold (SwiftUI's `LongPressGesture.sequenced(before: DragGesture)` gives no drag value before it moves).
- Run 1: `.agents/skills/layers/SKILL.md` already carries the page, chart-inventory and gesture rules ("Rule gaps"), since the code they describe has landed; Run 3 need not touch it again.
- Run 2: the nights chart is a shared `NightsChart` (in `NightlyDayPart.swift`), owned by `NightlyDayPart` and `RecoveryDay`, each holding its own `BodyModel(period: .week, endingOn: day)` and the scrub `selection`; the header scrub is `BodyModel.scrubText`. Tapping a night in it opens D on that night (`page.pick`).
- Run 2: Heart rate W/M/3M is `HeartRateDaysPart` + `HeartRateDaysModel` in `Pages/HeartRateDays.swift` (plan's name `HeartRateDays`); `PageKind.periods` is deleted and heart rate's picker shows all four views. `BodyModel.ticks` and `midday` became static so the heart-rate chart shares the date axis.
- Run 2: the D charts' scrub is `.holdThenDrag` and drives the header; `HourlyStepsChart` and `ReadingDayChart` take `selection:` and `scrub:` and lost their `ScrubLabel`; their scrub text is a static `scrubText(at:...)` the page turns into the header.
- Run 3: the Sleep chart is `SleepNightChart` in `Sleep/SleepNightChart.swift` (stages + overnight heart rate in one grid, selection binding in, `scrubText(at:sleep:heartRates:zone:)` out); `NightView` keeps the summary, a "Stages" card of stage rows and the Overnight rows; `SleepNightContent` is gone, `SleepDay` owns the selection and the empty states. The chart ticks every 5 minutes.
- Run 3: Stress `ThroughTheDayCard` is gone: `CalmDay` draws the chart card itself, and the "Through the day" title's meaning (`yours`, explanation) moved to `SignalPageModel.meaning`. `HourlyStressChart` takes `selection` (compact callers pass `.constant(nil)`), `takeLaunchScrub`, `scrub`; `StressModel` gained `takeLaunchScrub`, so `-VeselScrub 14:00` works on Stress.
- Run 3: the Stress header is the high-stress time for today too ("8 m high stress", line "Today · so far"); today's "now" level stays in the range line and the headline. Learning shows the learning wording as header and no chart, as before.
- Run 3: `ScrubLabel` deleted (nothing used it); `chartScrub` stays (`SignalChart`, `HeartRateDays` and every D chart use it). `docs/how-it-works/days.md` status is `Built`, not `Planned`. The AGENTS.md Factory `run` line lists no `-VeselPage`/`-VeselPeriod`, so it is unchanged.
- Review: the chart gestures are UIKit recognizers (`HoldToScrub`, a `UILongPressGestureRecognizer` of 0.25 s; `HorizontalSwipe`, a pan that only begins sideways) behind `chartScrub(_:style: .holdThenDrag)`, with the tap still a `SpatialTapGesture`. Checked in the Simulator: the SwiftUI `LongPressGesture.sequenced(before: DragGesture)` and `simultaneousGesture(DragGesture)` swallowed a vertical scroll that started on the chart, and a hold-then-drag to the right also started iOS 26's swipe back. Now the swipe back waits for the chart's recognizers, so it fires only off the chart. The hold scrubs as soon as it is recognized (no longer waiting for the finger to move). Hourly scrub lines snap to the middle of the hour.
