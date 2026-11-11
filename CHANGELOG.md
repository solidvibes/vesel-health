# Changelog

Written from the reader's side: what the thing does now, not what was refactored.
One plain sentence per entry.

## Unreleased

- While Polar finishes your night, Today says so and shows until when Vesel checks, instead of loading without end.
- Changing a Loop setting can no longer be cut off halfway and leave the Loop stuck; if the Loop is ever stuck saying it's busy for two hours, Today says so and shows how to restart it.
- Recovery now leads with a short verdict and shows each thing that went into it with a mark against your normal, and tapping one opens its page.
- HRV, resting heart rate, lowest heart rate, breathing and skin temperature now open with a picture of last night against your normal, and nights outside it are coloured on their chart.
- Sleep now shows Bedtime · wake, In bed and Efficiency first, then your normal, then the night's chart, each opening its own page, and shows your normal for time asleep as a picture.
- Sleep over weeks now shows stacked deep, light and REM bars for each night, with averages of In bed and Efficiency and your middle bedtime and wake time.
- Vesel now shows the workouts your Loop notices, with route, heart rate and cardio load.
- Loop & settings now lets you say which wrist you wear the Loop on, and sends it to the Loop.
- The Stress page now shows every 3-minute stress reading through the day, more of the time you wear your Loop gets a reading, and a gap says why.

## 0.1.0 — 2026-11-01

- Pairing now says to sync Polar Flow once before the factory reset, because the reset erases anything your Loop hasn't sent yet.
- The backup screens now say "your Mac" instead of "your Mac mini", since any Mac can keep the backup.
- The widgets' numbers and times now follow your text size.
- When Vesel can't read something, it says so and offers Try again, instead of loading forever.
- The morning sleep report is now on by default, and tapping it opens last night's Sleep page.
- If Vesel can't open its data, it now says so and lets you try again, instead of closing.
- Vesel is now open source under the Apache 2.0 licence.
- Loop & settings now credits Polar's SDK and the other libraries, and says Vesel is not a medical device.
- Vesel reaches your Loop again after iOS restarts it in the background, and stops retrying every few seconds when it can't.
- "I'm up" shows every morning until last night is in and works with your Loop out of reach: Vesel ends the night as soon as the Loop is near, and shows "Evaluating your night" meanwhile.
- Reads wait up to a minute for your Loop with a calm "Waiting for your Loop" card, never hang, and the "Reading your Loop" card appears only once the Loop answers.
- Sleep now shows as one blue bar per night on Body and on the Sleep page's week, month and 3 months, over your shaded normal.
- Vesel reconnects to the Loop before every read, so a dropped connection no longer stops syncing until the app is restarted.
- On a page, the title and the D · W · M · 3M switch now stay still while you swipe, and the next day or week shows its data under your finger.
- Swipe anywhere on a page to move a day, week or month; titles move into the top bar as you scroll.
- The band data report's first row no longer hides under the top bar.
- The Loop button turns orange when the Loop's battery is below 20 %.
- Sync now and I'm up keep reading after you leave Vesel, with a progress card you can cancel.
- Turn on Stand-up reminders in Loop & settings to get your Loop's sit-too-long alert on your iPhone.
- Vesel now also reads when your Loop checks in during the day, and catches up with a longer read while the phone charges.
- A read cut short in the background now keeps what it got, so steps and heart rate stay fresh.
- "Good morning — I'm up" is now the first card on Today, and Today says "Processing…" instead of showing the night before while last night is still coming in; Journal and the Sleep and Recovery pages do the same.
- Journal's week strip now runs Monday to Sunday, so each weekday keeps its spot.
