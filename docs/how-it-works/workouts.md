# Workouts

**Status:** Planned (`docs/plans/2026-11-03-workouts.md`, phases 1–5). Not built.

> Your Loop notices a workout by itself. Vesel reads it, shows it on the day, and uses it to explain your heart rate, stress and recovery.

## Intent
A run or a ride explained nothing before: it showed as a high-heart-rate stretch and stress readings skipped as exercise, and a low-recovery morning had no reason given. Workouts are read straight off the Loop, like everything else (decision `2026-11-03-workouts.md`). Never a training log: no weekly totals, no bests, no streaks.

## How it works

### On the Loop
- Vesel switches on the Loop's automatic training detection once: on the first read after this update, or after pairing. It keeps the Loop's own sensitivity and shortest workout if it has them, else Polar's defaults (sensitivity 50, 10 minutes). After that the band setting only changes from Workouts settings.
- The Loop starts and ends a workout itself. No GPS, no tap. The Loop has no screen and Vesel can't start one.
- Each finished workout is read on every read, and when the Loop says a workout started or ended (that notice also wakes a read, like a check-in). Read just after the Loop's sleep and daily summary parts, before the slow heart-rate and beat-to-beat downloads.
- What is read: sport (if the Loop gave one), start, length, calories, Polar's training load, the Loop's heart rate during it (one reading every second or so), and distance and route if the band ever has them. Kept as it came off the band, plus a typed row.
- A workout the Loop is still recording is not read until it ends. A workout whose files didn't all come back (the Polar SDK reports a failed file as missing) is read again next time.
- **Workouts stay on the Loop.** Vesel never deletes them. Only a factory reset (Forget this Loop) clears them; "Band storage is filling up" says workouts stay on the band.

### Route (phone GPS)
- When the Loop says a workout started and **Record my route** is on and location is allowed ("Always"), the phone records its own location until the Loop says it ended (at most 6 hours). The route is joined to the Loop's workout by time; points outside the workout are dropped.
- Points less exact than 25 m are dropped. Distance is the sum of the straight lines between the kept points; average speed is distance ÷ the workout's length.
- If iOS doesn't let the phone start in time, the route starts late or not at all. The workout is complete without one. Whether a background start works is checked on the owner's iPhone.
- In the Simulator, Features → Location → City Run or City Bicycle Ride plays a route while the fake band's workout runs.
- The route stays on the phone and the Mac backup, like every reading. No place names are looked up.

### What a workout shows
- **Sport**, first match:
  1. the Loop's own sport, when it gave one that isn't generic ("other indoor", "other outdoor" or none);
  2. with a route: average speed over 13 km/h is cycling, else running ("guessed from speed");
  3. no route: the sport you did most often within 2 hours of that time of day over the last 90 days, from workouts with a sport from the Loop or from you ("guessed from time of day");
  4. else "Workout".
  Guesses use only the sports switched on in Your sports. Ties go in the order Cycling, Running, Swimming, Strength.
- **Your fix:** a guessed sport shows a chip "guessed from speed · change". Tapping it (or the sport) opens a sheet with your sports and "Not a workout". Your choice is kept and never replaced by a later read of the band. "Not a workout" hides it everywhere and its time counts for stress again.
- **Effort:** Polar's training load for that workout (its cardio load; the older training-load number when the Loop gives only that), shown as Easy (under 60), Moderate (60–149) or Hard (150 and up), with the number. Tapping it shows where it came from: "Polar's training load for this workout: 87. Easy under 60, moderate 60–149, hard 150 and up." The cut-offs are provisional. No effort when the Loop gave no load.
- **Heart rate:** average and highest, from the Loop's workout record; the chart is the Loop's own readings during the workout (the 24/7 heart rate if the workout file had none).
- **Calories:** from the Loop.
- **Swimming:** whether the Loop records lengths or distance in water is not known. If it does: distance, pace per 100 m and a pool-length setting (a later change). If not (planned default): time and heart rate only, with the line "Heart rate at the wrist is less exact in water."

### Where workouts show
- **Journal:** a Workouts section between Night and Day for the picked day, one card per workout in time order: sport, start–end, length · effort word, a small heart-rate line. A card opens the Workout page.
- **Today:** one short line per workout started today, under the Steps card: "Run · 07:10 · 42 m · Moderate ›". Nothing when there was none.
- **Recovery headline:** when recovery is lower than usual or low and yesterday had a Moderate or Hard workout, the headline names it: "Low recovery after yesterday's hard ride." / "Recovery is lower than usual after yesterday's moderate run." (`headline` version 4). The highest-effort one is named; an Easy one isn't.
- **Charts:** the Heart rate page's day line, the Stress page's hourly bars and their glances on Today and Journal draw a purple block behind each workout's time. A finger inside it adds the sport ("14:05 · 142 bpm · Ride"). VoiceOver says "during a ride".
- **Stress:** readings inside a workout aren't counted (as well as the existing exercise rule); the Stress page's How it's worked out says how many were skipped as workouts.
- **Body:** nothing.

### The Workout page
Opened from a Journal card or Today's line. Top to bottom: the sport (with the guess chip) and the date and time ("Tue, Nov 3 · 07:10–07:52"); the route on a map with distance and average speed (only with a route); the heart-rate chart with average and highest (hold, then drag, to read); effort (word and number; tap for the source); calories; How it's worked out. No comparison with other workouts.

### Workouts settings
Loop & settings → Workouts (a pushed screen):

| Row | Default | Where it lives |
|---|---|---|
| Notice workouts by itself | On | The Loop (band first, then phone) |
| Sensitivity, 0–100 (higher notices more easily) | The Loop's own, else 50 | The Loop |
| Shortest workout, 5–60 min | The Loop's own, else 10 min | The Loop |
| Record my route | On | Phone |
| Your sports: Running, Cycling, Swimming, Strength | All on | Phone (only for guesses and the fix sheet; the Loop has no sport list) |

A band setting saves when you let go of the slider or pick a length: it waits for a running read, writes the Loop, then stores it on the phone. If the Loop doesn't take it: "Not saved. Your Loop didn't take the change, so nothing changed on your phone either. Keep the Loop close and try again." Record my route: turning it on asks iOS for location; if location is off for Vesel the row says "Location is off for Vesel in iOS Settings" with a link to Settings.

### Stored and backed up
- Tables: `workout` (typed, one per Loop workout, keyed by its start), `workout_file` (each file as it came off the band), `workout_choice` (your fix), `workout_route` (the phone's route). All go to the Mac backup over the existing pinned connection; nothing else leaves the phone.
- Worked out on read, not stored: sport guesses, effort words, distance and speed. Stress numbers that skip workouts are stored as before (`stress` version 3).

## Do / Don't
- Don't add effort up over days or weeks; no bests, no streaks, no "longest", no comparison with an earlier workout.
- Don't delete workouts from the Loop.
- Don't replace the owner's fix with a band re-read.
- Don't record location outside a workout the Loop started, and never log it.
- Don't start a workout from Vesel (later, if ever).

## Open questions
- Does the Loop give a sport for workouts it noticed itself, and which ids for swimming and strength? Checked on the owner's Loop.
- Does the Loop record distance or lengths when swimming? Decides the swimming case.
- Does a background location start from the Loop's notice work? Checked on the owner's iPhone.
- Does writing the detection setting leave the Loop's inactivity alert on? Checked after the first write.
