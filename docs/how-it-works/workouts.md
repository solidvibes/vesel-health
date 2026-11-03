# Workouts

**Status:** Partly built (`docs/plans/2026-11-03-workouts.md`): stored and backed up, read from the Loop with detection switched on, stress skips them, and the sport, load and route are worked out in VeselCore. Not yet read on the real Loop. Workouts settings and the route recording are built (the background start not yet tried on the owner's iPhone). The Workout page (with the route on Apple's map) and Journal's Workouts section are built; Today's lines, the headline and the chart blocks are planned.

> Your Loop notices a workout by itself. Vesel reads it, shows it on the day, and uses it to explain your heart rate, stress and recovery.

## Intent
A run or a ride explained nothing before: it showed as a high-heart-rate stretch and stress readings skipped as exercise, and a low-recovery morning had no reason given. Workouts are read straight off the Loop, like everything else (decision `2026-11-03-workouts.md`). Never a training log: no weekly totals for now (`docs/ideas/training-load-trends.md`), no bests, no streaks.

## How it works

### On the Loop
- Vesel switches on the Loop's automatic training detection once: on the first read after this update, or after pairing (Forget this Loop resets this, so a new Loop gets it too). It keeps the Loop's own sensitivity and shortest workout if it has them, else what the Polar SDK writes when there are none (sensitivity 50, 10 minutes). After that the setting only changes from Workouts settings; the phone keeps a copy, so the screen never has to ask the Loop.
- The Loop starts and ends a workout itself. No GPS, no tap. The Loop has no screen and Vesel can't start one.
- Every read lists all workouts on the Loop and reads the ones Vesel doesn't have, or whose files changed size. The Loop saying a workout started or ended also wakes a read, like a check-in. Read after skin temperature, before the slow heart-rate and beat-to-beat downloads.
- What is read: sport (if the Loop gave one), start, length, calories, Polar's cardio load and its own rating of it, the older training-load number, and the Loop's heart rate during it. Every file is kept exactly as the Loop sent it (distance and route too, if it ever has them), plus a typed row with what the screens show.
- Vesel asks the Loop whether a workout is running; that one isn't read until it ends. A workout that fails to come off the Loop is skipped and tried again on a later read (at most once an hour); the rest of the read carries on. A file that arrives but can't be read is noted and not fetched again unless the Loop's copy changes.
- **Workouts stay on the Loop.** Vesel never deletes them. Only a factory reset (Forget this Loop) clears them; "Band storage is filling up" says workouts stay on the band.

### Route (phone GPS)
- When the Loop says a workout started and **Record my route** is on and location is allowed, the phone records its own location until the Loop says it ended (at most 6 hours, one point every 5 seconds). The route is joined to the Loop's workout by time; points outside the workout are dropped. The route so far is written every minute and at the end; it is stored under its start time.
- Location "Always" lets the route start from the Loop's notice with Vesel in the background. With "While using" it starts only when the workout begins while Vesel is open.
- Points less exact than 25 m are dropped. Distance is the sum of the straight lines between the kept points; average speed is distance ÷ the time the route covers (first to last point). A route covering less than half the workout shows its distance and "Route covers 12 of 42 min", no speed, and isn't used to guess the sport.
- If iOS doesn't let the phone start in time, the route starts late or not at all. The workout is complete without one. Whether a background start works is checked on the owner's iPhone.
- In the Simulator, Features → Location → City Run or City Bicycle Ride plays a route while the fake band's workout runs.
- The route stays on the phone and the Mac backup, like every reading. No place names are looked up.

### What a workout shows
- **Sport**, first match:
  1. the Loop's own sport, when it gave one that isn't generic ("other indoor", "other outdoor" or none);
  2. with a route covering at least half the workout: average speed over 13 km/h is cycling, else running ("guessed from speed");
  3. no route: the sport you did most often within 2 hours of that time of day over the last 90 days, from workouts with a sport from the Loop or from you ("guessed from time of day");
  4. else "Workout".
  Guesses use only the sports switched on in Your sports. Ties go in the order Cycling, Running, Swimming, Strength.
- **Your fix:** a guessed sport shows a chip "guessed from speed · change". Tapping it (or "Change the sport" further down the page) opens a sheet with your sports and "Not a workout". Your choice is kept and never replaced by a later read of the band. "Not a workout" hides it everywhere and its time counts for stress again, worked out at once.
- **Load:** Polar's cardio load for that workout, as the number: "Cardio load 172". Beside it, Polar's own word for how it compares with your last 90 days (its rating 1–5), but only for ratings whose word has been confirmed on the owner's Loop; until then the number alone. When the Loop gives no cardio load, its older training-load number shows instead, labelled "Training load 140". No row with neither. Vesel makes no word of its own. Tapping it shows where it came from.
- **Heart rate:** average and highest, from the Loop's workout record; the chart is the Loop's own readings during the workout (the 24/7 heart rate if the workout file had none).
- **Calories:** from the Loop.
- **Swimming:** whether the Loop records lengths or distance in water is not known. If it does: distance, pace per 100 m and a pool-length setting (a later change). If not (planned default): time and heart rate only, with the line "Heart rate at the wrist is less exact in water."

### Where workouts show
- **Journal:** a Workouts section between Night and Day for the picked day, one card per workout in time order: sport, start–end, "24 min · load 172", a small heart-rate line. A card opens the Workout page.
- **Today:** one short line per workout started today, under the Steps card: "Cycling · 07:10 · 24 min · load 172 ›". Nothing when there was none.
- **Recovery headline:** when recovery is lower than usual or low and yesterday had a workout Polar rated 3 or higher (its middle rating or above), the headline names it: "Low recovery after yesterday's ride." / "Recovery is lower than usual after yesterday's run." (`headline` version 4). The one with the highest cardio load among those is named. Without Polar's rating, no workout is named.
- **Charts:** the Heart rate page's day line, the Stress page's hourly bars and their glances on Today and Journal draw a purple block behind each workout's time. A finger inside it adds the sport ("14:05 · 142 bpm · Ride"). VoiceOver says "during a ride".
- **Stress:** readings inside a workout aren't counted (as well as the existing exercise rule); the Stress page's How it's worked out says how many were skipped as workouts.
- **Body:** nothing.

### The Workout page
Opened from a Journal card or Today's line. Top to bottom: the sport (with the guess chip) and the date and time ("Tue, Nov 3 · 07:10–07:52"); the route on Apple's map with distance and average speed (only with a route; decision `2026-11-03-route-map.md`); the heart-rate chart with average and highest (hold, then drag, to read); load ("Cardio load 172", Polar's word when confirmed; tap for the source); calories; "Change the sport"; How it's worked out. No comparison with other workouts. Labels, distance and speed are worked out each time the page is read, never stored.

### Workouts settings
Loop & settings → Workouts (a pushed screen):

| Row | Default | Where it lives |
|---|---|---|
| Notice workouts by itself | On | The Loop (band first, then phone) |
| Sensitivity, 0–100 in steps of 5, "Rarely" … "Easily" | The Loop's own, else 50 | The Loop |
| Shortest workout, 5–60 min | The Loop's own, else 10 min | The Loop |
| Record my route | On | Phone |
| Your sports: Running, Cycling, Swimming, Strength | All on | Phone (only for guesses and the fix sheet; the Loop has no sport list) |

A band setting saves when you flip the switch, let go of the slider or pick a length: it waits for a running read, writes the Loop, then stores it on the phone. If the Loop doesn't take it: "Not saved. Your Loop didn't take the change, so nothing changed on your phone either. Keep the Loop close and try again." Record my route: while location isn't allowed the row says "Needs location · Allow"; only tapping Allow (or turning the switch on) asks iOS. Opening the screen never asks. If location is off for Vesel the row says "Location is off for Vesel in iOS Settings" with a link to Settings. With While using only, it says routes start only while Vesel is open, with the same link.

### Stored and backed up
- Tables: `workout` (typed, one per Loop workout, keyed by its folder on the Loop), `workout_file` (each file as it came off the band), `workout_choice` (your fix), `workout_route` (the phone's route). All go to the Mac backup over the existing pinned connection; nothing else leaves the phone. Opening a workout page with a route fetches Apple's map tiles for that area; the route is drawn on the phone.
- Stored as the Loop gave them: cardio load, Polar's rating, training load. Worked out on read, not stored: sport guesses, distance and speed. Stress numbers that skip workouts are stored as before (`stress` version 3).

## Do / Don't
- Don't add load up over days or weeks (for now); no bests, no streaks, no "longest", no comparison with an earlier workout.
- Don't put a word of Vesel's own on the load.
- Don't delete workouts from the Loop.
- Don't replace the owner's fix with a band re-read.
- Don't record location outside a workout the Loop started, and never log it.
- Don't start a workout from Vesel (later, if ever).
- Don't use the map for anything but tiles: no search, place names, directions or sharing.

## Open questions
- Which word goes with each of Polar's ratings 1–5? The SDK's comment says very low … very high; confirmed on the owner's Loop before any word shows.
- Does the Loop give a sport for workouts it noticed itself, and which ids for swimming and strength? Checked on the owner's Loop.
- Does the Loop record distance or lengths when swimming? Decides the swimming case.
- Does a background location start from the Loop's notice work? Checked on the owner's iPhone.
- Does writing the detection setting leave the Loop's inactivity alert on? Checked after the first write.
