# Design system

Clear glass. Approved 2026-10-26. Font: SF Pro (system), sizes map to Dynamic Type.

In code: colour sets in `ios/Vesel/Assets.xcassets`, everything else in `ios/Vesel/Theme/`.

## Colours

| Job | Light | Dark |
|---|---|---|
| background | #F3F3F1 | #0E0F11 |
| surface | #FFFFFF | #1A1C20 |
| text | #111113 | #F2F2F4 |
| muted text | #55555B | #A1A1AA |
| primary | #111113 | #F2F2F4 |
| on primary | #FFFFFF | #111113 |
| accent | #2F5FE0 | #7FA2FF |
| on accent | #FFFFFF | #111113 |
| error | #C42B1C | #FF7B6E |
| on error | #FFFFFF | #111113 |
| success | #22844A | #4ADE80 |
| recovery (data) | #2F9E5B | #4CC27D |
| sleep (data) | #3B6CF6 | #7FA2FF |
| stress (data) | #D9621B | #FF9A52 |
| workout (data) | #7A4FD6 | #B79BFF |

Surfaces are Liquid Glass (`.glassEffect`) at about 60% over one faint wash at the top right of the screen: sleep blue at about 10% with a fainter touch of recovery green (about 7%) over it, nothing lower down. Today's "something's off" adds a stress-coloured glow at the top at about 18%.

## Type

| Role | Font | Size | Weight | Line height |
|---|---|---|---|---|
| display | SF Pro Display | 34 | 700 | 1.1 |
| title | SF Pro Display | 28 | 700 | 1.15 |
| heading | SF Pro Text | 20 | 600 | 1.25 |
| body | SF Pro Text | 17 | 400 | 1.45 |
| label | SF Pro Text | 15 | 600 | 1.3 |
| small | SF Pro Text | 13 | 500 | 1.35 |

Display = `.largeTitle`, title = `.title`, heading = `.title3`, body = `.body`, label = `.subheadline` semibold, small = `.footnote`.

## Spacing

Base: 4. Scale: 4, 8, 12, 16, 20, 24, 32, 40, 48. Screen edges: 20.

## Corners

| Part | Radius |
|---|---|
| small | 12 |
| card | 24 |
| sheet | 32 |

## Icons

SF Symbols, outline (regular). Filled only for the selected tab.

## Illustration

None.

## Components

- Button: primary (ink pill), secondary (glass), destructive (error). Normal, pressed, disabled.
- Text field: label above, 48 pt tall. Normal, focused, error (red border + icon + words), disabled.
- Card: glass, 24 radius, 16–20 padding.
- Metric card: label, big value with unit, change vs usual with an arrow.
- Range line: recovery, sleep, stress, each in its data colour; Recovery turns to the stress colour when Polar says compromised or worse. A 10 pt track (muted), your normal shaded on it in the data colour at about 35 %, a 14 pt dot: filled = inside your normal, hollow (3 pt ring) = outside it, below or above. No line while still learning (the learning words instead), the faint empty track and no dot = no data. The value shows beside it as a word; colour is never the only signal (VoiceOver says the state). On the round Lock Screen spot it bends into a 270° arc with the word in the middle. The app icon keeps its one ring.
- Workout block: behind a day's heart-rate line or stress bars, the workout's time at 18 % purple with a 3 pt full-purple top edge; under a page chart a line names it ("Purple: ride 18:30–19:45").
- Day dots: three 6 pt dots per day (recovery, sleep, stress): filled = inside, hollow = outside, a small muted dot = learning, an empty slot = no data.
- List row: 52 pt tall, label left, value right. Normal, pressed, disabled.
- Tab bar: floating glass pill, up to 4 tabs.
- Empty state: outline icon, one line title, one line what happens next.
- Error message: glass card, warning icon, what happened, one action, plus at most one quiet link row (title and chevron) to where it's explained.

## Accessibility

- Contrast ≥ 4.5:1 for text (3:1 large text and chart marks). Checked: text 17:1 both modes; muted 6.4:1 light, 7.3:1 dark; accent 5.5:1 and error 5.7:1 on white; data colours ≥ 3:1 on background. Workout purple: 4.8:1 on the light background, 5.4:1 on white, 8.4:1 on the dark background, 7.4:1 on the dark surface, so it also passes as text. It is close to sleep blue and stress orange in lightness, so a workout block is never told apart by colour alone: it has a top edge, and the scrub text and VoiceOver name the sport.
- Body 17 pt; layout holds at the largest Dynamic Type sizes.
- Tappable things ≥ 48 × 48 pt.
- Colour never alone: errors have an icon and words; changes have an arrow.
