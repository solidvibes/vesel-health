# What tends to help

**Status:** Built. Not yet checked on the real band.

> When something was off, the Recovery, Sleep or Stress page says what tends to help, in plain general advice.

## Intent
Turn "something is off" into something to do, without nagging (decision `2026-10-28-what-helps.md`).

## How it works
- A card "What tends to help" on the Recovery, Sleep and Stress pages, after the day's content and its "How it's worked out", only when that page had something off; past days too.
- What counts as off: the Recovery line below; HRV lower or resting heart rate higher than usual (beyond 1 SD); breathing or skin temperature far from usual (beyond 2 SD); short sleep when sleep was the night's biggest departure; the Sleep line below or above; the Stress line above.
- 3 to 5 tips from a fixed, reviewed list bundled with the app, chosen by what was off: low recovery or HRV, a higher resting heart rate, breathing or skin temperature far from usual, a short or a long night, more stress than usual.
- Your own numbers fill in where they fit: your usual bedtime (`usualBedtime` v1: median sleep start of the previous 28 nights, at least 7, rounded to 5 minutes; its working-out opens under the card when a tip names it) and, on today's Stress page only, the day's busiest 2 hours (stored `stress.busiestSpan`).
- Labelled "General advice for most people, not medical advice."
- On the page only: never on Today, a widget or a notification.
- Later, with tags on a day (a later idea): "From your own nights", counted only from your own nights.

## Do / Don't
- Don't write advice anywhere but the one list (`WhatHelps` in VeselCore).
- Don't make medical claims; point to a doctor only plainly, when something keeps happening and you feel unwell.
- Don't show advice on a good day.
