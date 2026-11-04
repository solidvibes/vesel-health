# Meanings

**Status:** Built (companion plan, phase 3). The recovery card's term links come with phase 4. Not yet read on the real iPhone. Built on the pages; planned on Body (tabs layout plan).

> Tap a title or a word in the link colour to read what it means for you: what it is, whether more is good, what's normal, what affects it, your own number, and how the band knows.

## Intent
Screens said where Polar keeps a number, not what it means. One set of meanings, written once, answers "what does this mean for me" everywhere, without info buttons and without breaking "every number can be explained".

## How it works
- One glossary in the app, bundled, offline. No network.
- 18 entries: deep sleep, light sleep, REM sleep, awake, sleep time, HRV, resting heart rate, lowest heart rate, breathing, skin temperature, recovery (Nightly Recharge), usual range, stress, high stress, heart rate, how the band knows, Heart fitness, VO2max (both in the Heart group, each ending with "It's an estimate").
- Workouts (`workouts.md`): two more entries in the Movement group, Workout and Cardio load (Polar's load for one workout, not added up). Opened from the Workout page's title and load row (with that workout's load as Yours).
- Each entry, in order: what it is; good or bad; a lot or a little; what's normal; what affects it; your number for the day shown ("Yours"); how the band knows; then "How it's worked out", folded, with the number's own explanation (text, method, version).
- Titles and words that have a meaning open the meaning sheet when tapped; they have no underline (a word in running text is in the link colour), and VoiceOver says "what it means". The rest of a card still opens what it opened before. No info buttons.
- The text is `Glossary` in VeselCore (code, no I/O); one sheet is hosted once by the tab screen and opened with a request (term, the screen's own "Yours" line, the explanations to fold). Terms in running text are `vesel-term:` links the app handles itself.
- Where: Body card titles (the rest of a card still opens its chart), page titles, the "usual range" words on Body, the Sleep page's stage rows and Time asleep (a row opens the sheet instead of expanding), the Stress page's title, the Heart rate page's title. Heart fitness' card and page titles and the VO2max row on its page. Not on Today. The recovery card's title and each contributor row open it too.
- Loop & settings → Help → What things mean: the same entries as a list, without a "Yours" line.

## Planned
- Three more entries in the Sleep group (`docs/plans/2026-11-04-recovery-sleep-polish.md`): In bed, Efficiency, Bedtime and wake, opened from their new pages' titles.
- Recovery's contributor rows stop opening the meaning sheet: a row opens that signal's page, whose title opens the meaning.

## Do / Don't
- Don't write meaning text anywhere but the glossary.
- Don't make medical claims; compare with your own usual first.
- Don't hide how a number is worked out: it stays in the sheet, folded.
