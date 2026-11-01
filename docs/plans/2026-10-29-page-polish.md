---
status: implemented
---

# Page polish: low-battery ring, band report push, page swipes with the title in the bar
**Date**: 2026-10-29
**Status**: Implemented 2026-10-29 (owner checks on the iPhone still open)
**Touches**: `docs/design/screens.md`, `docs/how-it-works/band-sync.md`, `.agents/skills/layers/SKILL.md`, `CHANGELOG.md`

## TL;DR
- Three phases: 1 low-battery ring, 2 band data report push fix, 3 page swipes + title in the bar (starts with a spike).
- Request 4: `SignalPage` already serves all ten signal pages; only Heart fitness (exempt) sits outside. Nothing moves.
- Phase 1: below 20 % battery the tab bar's ring turns the stress colour; VoiceOver "Battery low"; Battery row "18 % · Low".
- Phase 1: `BandInfo.isBatteryLow` (VeselCore), `observeBand()` (VeselStorage), observed in `MainTabs`.
- Phase 2: the band data report opens through `TodayRoute.bandDataReport`, not a destination link. No shared refactor unless a repro shows a shared cause.
- Phase 3 step 1: a throwaway Simulator spike proves the pager against swipe back, scrub and vertical scroll before anything is built.
- Phase 3: the whole page is a native horizontal pager of period pages; a sideways drag anywhere pages.
- Fallback if the spike fails: keep ‹ › and the chart swipe, and slide the whole page in with a push transition.
- Page ids are (period, day); only the current page observes the database; neighbours show a skeleton.
- Title moves into the bar once the big title scrolls under it: Signal pages and Heart fitness.
- `PeriodWindow.pages` (VeselCore, tested) lists the pages from the first day with data to today.
- The chart's own swipe goes; hold-to-read and tap-a-day stay.
- No migration, nothing leaves the phone, no risk area.

## Context
The owner, after using the one-page-per-signal build on the iPhone:
1. On the band data report (and maybe other screens) the top item sits behind the top bar and can't be tapped.
2. Heart rate on D: swiping only works on the chart and looks strange; the page doesn't move. Wanted: a swipe anywhere moves to the previous or next period with the whole page sliding, on every view, without losing the finger scrub, vertical scroll or swipe back.
3. Scrolling up on Heart rate, "Heart rate" should move into the top bar beside back.
4. Do it once in the shared page so every signal benefits.
5. Below 20 % Loop battery, the ring at the end of the tab bar turns orange/yellow, with a non-colour signal too.

Found in the code:
- Pushed screens hand-roll `ZStack { BlobBackground(); ScrollView { … } }`. `TopFade` is on `LoopSettingsView`, `SyncingView`, `WhatThingsMeanView`, `AboutYouEditView` and `TabScreen`; not on `SignalPage`, `FitnessView` or `BandDataReportView`.
- `LoopSettingsView` opens the band data report with a destination `NavigationLink("Band data report") { BandDataReportView(…) }` inside the path-driven `NavigationStack`; it is the only screen pushed that way. `TodayRoute.bandDataReport` is already registered on Today's stack.
- Request 1 check (planner, current main build, fresh iPhone 17 Pro Max Simulator, iOS 26.5, default text): Loop & settings and the band data report, opened by launch argument and by tapping through: every first row starts below the bar. Not reproduced. The report's first row, "Live heart-rate stream · On/Off", is a read-only status, not a switch: a tap on it never does anything.
- `SignalPage` serves Recovery, Sleep, Stress, Heart rate, Steps, HRV, Resting HR, Lowest HR, Breathing and Skin temperature (`PageKind`, `pageDestinations` on all three stacks). The D parts (`RecoveryDay`, `SleepDay`, `CalmDay`, `HeartRateDay`, `StepsDay`, `NightlyDayPart`) and the period parts (`OverTimePart`, `HeartRateDaysPart`) are its children. The only other full page is Heart fitness (`FitnessView`), exempt from D·W·M·3M by the 2026-10-28 decision.
- Paging today: each chart has a `HorizontalSwipe` (UIKit pan, sideways, ≥ 40 pt) calling `page.page(±1)`; the part is swapped with `.id(position)` and no transition: the "strange" jump. Off the chart, a right swipe is the iOS 26 content swipe back.
- Battery: `BandInfo.batteryPercent` is written by `BandSync` on every read (battery/charging changes wake a read, `band-sync.md`). Only Loop & settings reads it, once on load. The ring is `LoopRing`, a template `UIImage` (animated while reading) tinted by the tab bar's `.tint(primary)`.

## Constraints
- Rules: `AGENTS.md` (non-negotiables, Factory `layers`, `risk`), `.agents/skills/layers/SKILL.md`, `.agents/skills/testing/SKILL.md`; `.agents/skills/data/SKILL.md` for `observeBand` (read only).
- Packs: none listed in `docs/stack.md` (blank 0.1.0).
- `ios/Vesel/Theme/` is compiled into the widget extension and its tests: anything added there takes plain values only.
- A page gets its day from its route; only `days.firstDay` is read, to bound paging.
- Never nag: the ring is quiet; no notification, nothing on Today.
- Colour never alone: VoiceOver value and the Battery row's words.
- iOS 26, Liquid Glass, Reduce Motion, VoiceOver, largest text sizes, no new dependencies.
- Risk areas: none.

## Approach

### Phase 1 — low-battery ring
- VeselCore `BandInfo.isBatteryLow: Bool` (`batteryPercent < 20`; nil → false). No test (it would restate the constant).
- VeselStorage `observeBand() -> some AsyncSequence<BandInfo?, any Error>` in `Observations.swift` (GRDB `ValueObservation` on the band row).
- `MainTabs`: `@State lowBattery`, read in a `.task(id: isActive)` loop over `observeBand()`.
- `LoopRing.image(reading:reduceMotion:low:)`: when low, frames are tinted with the Stress colour asset (`UIImage.withTintColor(UIColor(named: "Stress")!, renderingMode: .alwaysOriginal)` on the existing template frames), so light/dark resolve dynamically. Cache per `low` only (idle, still, turning × 2).
- Accessibility value: "Reading", "Battery low", or "Reading, battery low".
- Loop & settings Battery row: "18 % · Low" when low.
- Colour: the stress colour, the system's warm "look here" (Today's glow, compromised recovery), ≥ 3:1 as a mark on the glass bar in both modes; no yellow exists in the system.
- The ring shows the battery as of the last read (intended): it clears at the first read after charging, and charging changes wake a read.
- First check in the Simulator that the search-role tab keeps an `.alwaysOriginal` image's colour. If iOS forces it to one colour, stop and report (open question 3).

### Phase 2 — band data report push (request 1)
The only screen pushed with a destination `NavigationLink` inside the path stack is the band data report, and it is where the owner saw the problem. Fix: `NavigationLink(value: TodayRoute.bandDataReport)`, like Syncing and What things mean. Then reproduce on the owner's size (iPhone 15 Pro Simulator, iOS 26.x), default and largest text, opening each pushed screen by tapping from its tab. A shared frame (one pushed-screen scroll for all screens) is done only if that repro or the owner's screenshot (open question 1) shows a shared cause; otherwise it is not built.

### Phase 3 — page swipes and the title in the bar

**Step 1: spike (throwaway, not committed).** On the iPhone 17 Pro Max Simulator, iOS 26.5: a pushed screen with a paged horizontal `ScrollView` (`LazyHStack`, `containerRelativeFrame`, `.scrollTargetBehavior(.paging)`, `scrollPosition(id:)`), each page a vertical `ScrollView` holding a chart with the existing `HoldToScrub`. Record:
1. edge swipe back on a middle page: goes back, or pages?
2. right swipe from mid-screen on the first page: goes back, or rubber-bands?
3. hold then drag on the chart: reads without paging?
4. vertical scroll starting on the chart and on cards: scrolls?
5. the iOS 26 bar's soft scroll edge follows the inner vertical scroll?
6. opening at the last page (`.defaultScrollAnchor(.trailing)` / position set on appear) shows that page, not page 0; inserting earlier pages in front keeps the shown page.

Go if 1 goes back and 3, 4, 6 hold. If 5 fails, `SignalPage` gets `TopFade`. Write the result of 2 into this plan and `screens.md` (whichever happens is accepted). **Fallback** if 1, 3 or 6 fails: no pager. Keep ‹ › and the chart swipe as today, and on every move slide the whole page content in from the side it came from (`.transition(.push(from:))` on the part keyed by position; no slide with Reduce Motion). The owner confirms (open question 2) before step 2 either way.

**Pager (if the spike passes).**

```
SignalPage
  ScrollView(.horizontal) · paging · scrollPosition(id: $current) · defaultScrollAnchor(.trailing)
    LazyHStack(spacing: 0) {
      ForEach(model.pages, id: \.self) { id in          // PageID(period, day)
        PeriodPage(id)                                  // full width
          = ScrollView { TermTitle · picker · part(id) }  // the BlobBackground behind the pager
      }
    }
  .barTitle(kind.title, shown: model.titlePassed)
```

- **Model.** `SignalPageModel` keeps `period`, `day` and `end` as today (so switching D ↔ W/M/3M behaves as now: to a period opens the window holding the day; back to D keeps the day). `pages: [PageID]` with `PageID = (period, day-or-end)`, built from `PeriodWindow.pages`. The pager's position writes `day` (D) or `end`. ‹ › and the picker set it, animated unless Reduce Motion. When `firstDay` arrives the list is rebuilt without animation, keeping the current id.
- **Only the current page loads.** Parts read an `isCurrentPage` environment value. Their observation `.task(id:)` keys include it and return when not current, so neighbours show the skeleton until they become current, and N pages never re-fetch on a band write. A page scrolls to its top when it becomes current. Only the current part sets `page.meaning`; off-screen pages are `accessibilityHidden`.
- **Gestures.** `ChartScrubStyle.holdThenDrag` loses `onSwipe`; `HorizontalSwipe` and the swipe half of `SwipeDelegate` are deleted. The hold, tap-to-pick on W/M/3M and "the system swipe back waits for the hold" stay. `SignalChart.onSwipe` and every `onSwipe: { page.page($0) }` go.
- **`PeriodWindow.pages(period:holding:firstDay:today:)`** (VeselCore, pure): window ends, oldest first, from the end holding `min(firstDay, holding)` up to today, stepping by the period (D: every day). `firstDay` nil: only the window holding `holding`. Replaces `canPageEarlier`.

| | Paged scroll of periods (recommended, if the spike passes) | Fallback: ‹ › and chart swipe, page slides in |
|---|---|---|
| What you get | Swipe anywhere; the neighbour slides in under the finger; system physics | Swipe on the chart only (as today), but the whole page slides instead of jumping |
| Cost later | Neighbours exist as skeletons; gesture priority depends on iOS's scroll views | Owner's "swipe anywhere" not met |

**Title in the bar.** `.barTitle(_ title: String, shown: Bool)` in Theme: a `ToolbarItem(placement: .principal)` with the title in the headline font, `opacity(shown ? 1 : 0)`, 0.2 s ease (none with Reduce Motion), hidden from VoiceOver. The page watches its own big title: `onGeometryChange(for: Bool.self) { $0.frame(in: .scrollView).maxY < 0 }`. On `SignalPage` the current page writes `model.titlePassed`, and recomputes it when it becomes current. `FitnessView` does the same with its own state. Alternatives ruled out: the system large title can't open the meaning; toggling `.navigationTitle` re-lays-out the bar.

**Recorded behaviour this changes.** `screens.md` and the 2026-10-28 plan: "a quick horizontal swipe on the chart pages … a right swipe off the chart, or from the edge, goes back". With the pager: a swipe anywhere pages; the edge goes back; the first page as the spike records. The decision `2026-10-28-one-page-per-signal.md` ("‹ › or a swipe moving one period") still holds.

## Files

Phase 1
- `ios/Packages/VeselCore/Sources/VeselCore/Models/BandInfo.swift` — `isBatteryLow`.
- `ios/Packages/VeselStorage/Sources/VeselStorage/Observations.swift` — `observeBand()`.
- `ios/Vesel/Loop/LoopRing.swift` — low frames tinted with the Stress asset.
- `ios/Vesel/RootView.swift` — observe the band; ring image and accessibility value.
- `ios/Vesel/Loop/LoopSettingsView.swift` — Battery row "· Low".
- A low-battery fake-band scenario via `ios/Tools/make-fixtures.swift` if none exists (never hand-edited).
- `docs/design/screens.md`, `docs/how-it-works/band-sync.md` (Built), `CHANGELOG.md`.

Phase 2
- `ios/Vesel/Loop/LoopSettingsView.swift` — band data report link by value.

Phase 3
- `ios/Packages/VeselCore/Sources/VeselCore/Analysis/PeriodWindow.swift` — `pages`; drop `canPageEarlier`.
- `ios/Packages/VeselCore/Tests/VeselCoreTests/PeriodWindowTests.swift` — tests for `pages`.
- `ios/Vesel/Theme/BarTitle.swift` — new: `.barTitle(_:shown:)`.
- `ios/Vesel/Pages/SignalPage.swift` — pager, `PageID`, `isCurrentPage`, current-page meaning and title.
- `ios/Vesel/Body/FitnessView.swift` — bar title.
- `ios/Vesel/Theme/ChartScrub.swift` — drop `onSwipe` and `HorizontalSwipe`.
- `ios/Vesel/Body/BodyCard.swift` — `SignalChart` drops `onSwipe`.
- `ios/Vesel/Pages/OverTimePart.swift`, `HeartRateDays.swift`, `HeartRatePage.swift`, `SleepPage.swift`, `StepsPage.swift`, `CalmPage.swift`, `NightlyDayPart.swift`, `RecoveryPage.swift` — no `onSwipe`; observe and set meaning only when current.
- `.agents/skills/layers/SKILL.md` — page-swipe rule (end state, Rule gaps).
- `docs/design/screens.md`, `CHANGELOG.md`.

## Steps

### Phase 1 — battery ring
- [x] 1. Simulator check that the search-role tab keeps an `.alwaysOriginal` colour; if not, stop and report.
- [x] 2. `isBatteryLow`, `observeBand()`, `MainTabs` observation, `LoopRing` low frames, accessibility value, Battery row words.
- [x] 3. Docs to Built; CHANGELOG ("The Loop button turns orange when the Loop's battery is below 20 %.").

### Phase 2 — band data report
- [x] 4. Link by value; repro on iPhone 15 Pro Simulator (default and largest text, every pushed screen by tapping). Write the result under Verification. Shared fix only on a shared cause.

### Phase 3 — page swipes and title
- [x] 5. Spike (above); write results into this plan; owner confirms pager or fallback.
- [x] 6. `PeriodWindow.pages` with tests; `SignalPageModel.pages`.
- [x] 7. Pager in `SignalPage` (or the fallback transition); current-page-only observation, meaning, VoiceOver; scroll to top on becoming current.
- [x] 8. Remove the chart swipe (pager only); keep hold, tap-to-pick and the swipe-back wait.
- [x] 9. `.barTitle` on `SignalPage` and `FitnessView`.
- [x] 10. Simulator checks; `screens.md` to Built; layers rule; CHANGELOG ("Swipe anywhere on a page to move a day, week or month; titles move into the top bar as you scroll.").

## Decisions
1. **agent's** — Request 4: `SignalPage` already serves all ten signal pages; nothing moves. Heart fitness stays outside (exempt) and gets the bar title.
2. **agent's** — Request 1: targeted fix (report pushed by route value), no shared frame unless a repro shows a shared cause (review 6).
3. **open until the spike, owner confirms** — Page swipes: native pager of whole period pages; fallback named above (review 1).
4. **agent's** — Page ids are (period, day); only the current page observes; neighbours show a skeleton (review 2, 3).
5. **agent's** — `day` and `end` stay separate, so D ↔ W/M/3M switching behaves as today (review 12).
6. **agent's** — A new current page opens at its top.
7. **agent's** — Paging stops at the first day with data (or the opened day if earlier); with no data, one page.
8. **agent's** — Title in the bar: principal toolbar title that fades in, driven by the page's own title frame (review 9); not the system large title.
9. **agent's** — Low battery: below 20 % (owner), stress colour (owner said orange/yellow), VoiceOver "Battery low", Battery row "18 % · Low", as of the last read; no notification.
10. **agent's** — No test for the 20 % threshold; `PeriodWindow.pages` is tested.
11. **agent's** — First-page right swipe: whatever the spike shows is accepted and recorded (iOS default), not fought.
- **mine** (owner, 2026-10-29) — Request 1: fix the band data report now; the owner sends a screenshot later, and a wider fix only if it shows another screen.
- **mine** — Page swipes: whole-page pager if the spike passes (edge swipe-back, scrub, vertical scroll, opening position all hold); otherwise the named fallback (‹ › and chart swipe, whole page slides in). No extra owner stop between spike and build.
- **mine** — If iOS forces the ring button to one colour: the ink ring with a small orange dot.

## Verification
- `checks.fast` and `checks.full` from the contract.
- VeselCore: `PeriodWindow.pages` for D, W (first day mid-window), 3M, `firstDay` nil, holding before `firstDay`.
- Simulator (fresh iPhone 15 Pro and 17 Pro Max, iOS 26.5; delete after), `-VeselScenario normal -VeselNow 2026-10-25T15:00:00Z`:
  - Phase 1: battery 76 % → ink ring; low-battery scenario → orange ring in light and dark, also while turning; VoiceOver value "Battery low"; Battery row "18 % · Low".
  - Phase 2: band data report opened by tapping from Loop & settings: first row below the bar; every pushed screen at default and largest text.
  - Phase 3 (pager): Heart rate D, W, M, 3M and Sleep/Steps D: drag sideways from cards, header and chart → the whole page slides; at today it rubber-bands; first page as recorded by the spike; edge swipe back on a middle page goes back. Vertical scroll from chart and cards. Hold then drag reads, doesn't page. Tap a day on W → D. ‹ › and the picker move the page. Opens on the route's period, not page 0; a late `firstDay` doesn't jump. Heart rate 3M: drag back 10 pages, memory and database reads stay flat (one observation at a time).
  - Phase 3 (title): scroll up → title in the bar; down → gone; swipe to a neighbour → the bar title matches that page; Reduce Motion → no fade. Heart fitness the same.
- **Phase 2 result** (fresh iPhone 15 Pro Simulator, iOS 26.5, deleted after): reproduced. Opened by tapping from Loop & settings scrolled to its end, the band data report's first row ("Live heart-rate stream") sat under the bar and stayed there at the scroll top, with the link by value too; opened by launch argument it was fine. With `TopFade` on the report (as every other pushed screen except the pages has) it opens below the bar, at default and at the largest text. What things mean (tapped from a scrolled Loop & settings) and the Steps page (tapped from a scrolled Body) open below the bar without a change, so no shared cause was found and no shared frame was built. Syncing and the other pages were not re-checked at the largest text.
- **Owner only (iPhone):** request 1 gone on the real phone; swipe feel and edge swipe back; scrub haptics; Heart rate 3M with real data; the orange ring the next time the Loop is low.

## Spike result
iPhone 17 Pro Max Simulator, iOS 26.5, throwaway pager on Heart rate D (5 pages, 3 more inserted in front after 3 s), driven with Simulator touches; not committed.
1. Edge swipe on a middle page: goes back (to Today).
2. Right swipe from mid-screen on the first page: stays on the first page (bounces); it does not go back.
3. Hold, then drag on the chart: the header reads "65 bpm · 18:20 · Today" with the line on the chart; the page does not move.
4. Vertical scroll starting on the chart and on the cards: scrolls.
5. Soft scroll edge under the bar: a faint edge showed, but not clearly enough to call it; `SignalPage` gets `TopFade` (the conservative branch).
6. Opens on the last page, not page 0; inserting three pages in front keeps the shown page.

Go: 1, 3, 4 and 6 hold. The pager was built.

## Deviations
- Phase 3: only the shown page builds its part; the neighbours draw a skeleton instead of building the part with an `isCurrentPage` key in each part's observation. Same effect (one observation at a time, one meaning), and no part changes. A page that becomes the shown one scrolls to its top through its own `ScrollPosition`.
- Phase 3: the switch (D · W · M · 3M) rebuilds the row for the new view without a slide; only ‹ › slide (none with Reduce Motion). A tap on a day in W opens D on the right page.
- Phase 3: the bar title shows once the page has scrolled past its big title (`onScrollGeometryChange`: scrolled distance > top padding + title height), not by the title's frame in `.scrollView` space, which starts behind the bar.
- Phase 3: Heart rate 3M has one page with the Simulator's 30 days, so "drag back 10 pages" ran on Heart rate D: 10 pages back, app memory 311.8 MB → 314.2 MB.
- Phase 3: Heart fitness's bar title was not seen in the Simulator: with 30 days it shows the learning card, which doesn't scroll even at the largest text. Same code as the signal pages, where it was seen.
- Phase 3: `TopFade` alone left the header readable behind the bar title on the signal pages. The bar's scroll edge follows the horizontal pager, not the page's own vertical scroll, so the pager (and Heart fitness's scroll) get `.scrollEdgeEffectStyle(.hard, for: .top)`: content is cut at the bar's bottom edge. On the inner vertical scroll it had no effect.
- Fix after the owner's iPhone check (2026-10-29): the title and the switch no longer slide; one vertical scroll holds them over the horizontal row, so the title scrolls away and the bar title follows that one scroll (the per-page vertical scrolls, their title tracking and scroll-to-top are gone; the hard scroll edge moved to the vertical scroll). The current page and one on each side build their part, so the neighbour shows data mid-swipe; pages further out stay skeletons. Each part gives its meaning to its own page id through `\.setPageMeaning`, so a neighbour never overwrites the title's meaning. A lazy row doesn't grow with its pages, so the row takes the tallest built page's height. Pages already sat edge to edge (spacing 0); the space seen between cards mid-swipe is the two pages' 20 pt side margins, which stay.
- Phase 3: Reduce Motion was not switched on in the Simulator; the ‹ › slide and the title fade are switched off in code.
- Phase 2: the value link alone did not fix the band data report on the iPhone 15 Pro Simulator; adding `TopFade` (the other pushed screens' top fade) did. Why the missing fade moves the content under the bar is not known; it is SwiftUI's layout, not our code. Both changes ship.
- Phase 1: the search-role tab keeps an `.alwaysOriginal` image's colour (iPhone 17 Pro Max Simulator, iOS 26.5): the ring is the stress colour in light and dark, idle and turning, so no dot was needed. The low-battery Simulator scenario is `-VeselScenario lowBattery` (the fake band reports 18 %), set in `FakeScenario`/`FakeWearableSource` like `bandFull`, not through `make-fixtures.swift`: battery is not a fixture file.

## Open questions for the owner
1. Request 1: a screenshot of the screen where the top item sat behind the bar. It didn't happen on the Simulator; on the band data report the "Live heart-rate stream" row only shows On/Off and isn't a switch.
2. Page swipes: after the spike, confirm the whole page (title, switch, chart, cards) slides with your finger, the next day visible under it. Fallback if iOS won't let swipe back and paging live together: swipe stays on the chart, but the whole page slides instead of jumping.
3. If iOS won't colour the ring button: a small orange dot on the ring (recommended), or nothing (only the Battery row's words).

## Rule gaps
- (end state, phase 3) `.agents/skills/layers/SKILL.md`, the "Page charts scrub after a short hold so a swipe can page" bullet becomes: "A signal page is a horizontal paged scroll of whole period pages keyed (period, day) from `PeriodWindow.pages`; a sideways drag anywhere pages. Only the current page observes the database, sets the meaning and the bar title; off-screen pages are hidden from VoiceOver. Page charts scrub after a short hold (`chartScrub(_:style: .holdThenDrag)`, a UIKit long press that fails if the finger moves first); no chart has its own swipe. A SwiftUI `DragGesture` or `LongPressGesture.sequenced` on a chart inside a `ScrollView` swallows the page's scroll. Glances keep the instant scrub." (If the fallback ships instead, only add: "a move slides the whole page in with a push transition".)
- (end state, phase 2) `.agents/skills/layers/SKILL.md`: "On the path-driven stacks, push with a route value, never a destination `NavigationLink`."
- (end state, phase 1) `.agents/skills/layers/SKILL.md`: "The tab bar's ring reads the band through `observeBand()`; low battery is `BandInfo.isBatteryLow`."
