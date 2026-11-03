# Widgets

**Status:** Built. Checked on the real phone. Plans: range lines and the lock-screen arc, links to the pages. The medium widget's headline is the new one.

> Headline numbers on the home screen and lock screen, without opening Vesel.

## Intent
A glance is enough most days (decision `2026-10-26-summary-first.md`).

## How it works
- Home-screen widgets sit on the faint wash under a surface-coloured layer (about 78 %), so labels and values keep contrast 4.5:1 or more in light and dark; a stale widget is still dimmed.
- Home screen: small Recovery line, small Stress now, medium headline (`headline` v4, see `recovery.md`; it names yesterday's workout like Today's) + three lines; lock screen: a round arc and a two-line Recovery and sleep.
- Widgets read what Vesel already stored (one quick read-only look, then close); they never talk to the band.
- Updated after each sync that read the band (fully or partly), and asked to refresh hourly (iOS decides when).
- More than 12 hours since the band was last read all the way through: dimmed, with the time it's from. First week: "Your usual range appears after 7 nights · N of 7" under the Recovery line (the line itself is replaced by the learning words).
- Tap opens Today (`vesel://today`, the medium widget) or the page over Today: `vesel://recovery` (small Recovery, the round lock widget), `vesel://sleep` (the rectangular lock widget), `vesel://stress` (Stress now). The old `night` link goes nowhere.
- The Recovery line is the warm colour when Polar says compromised or worse, green otherwise.
- If the database is missing or the app has not brought it up to date yet, widgets say "No data yet".
- Every widget line follows the in-range rule (`days.md`): your normal shaded, a filled dot = inside, a hollow dot = outside (below or above), the learning words instead of a line = learning. The round lock-screen spot draws the same as a 270° arc with Polar's word in the middle; the rectangular one (still the same widget, now "Recovery and sleep") has a Recovery and a Sleep line and opens the Sleep page. Stress now keeps its name and its live word with the day's stress line; the medium widget's third line is titled "Stress". The lock-screen Recovery circle shows Polar's word in the middle of its arc.
- The line states are worked out from stored numbers in the one read-only look (as the headline is); the widget itself works nothing out.

## Do / Don't
- Don't put buttons on widgets that pretend to sync.
