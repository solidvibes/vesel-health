# Pairing

**Status:** Built. Checked with the real Loop: factory reset and pairing, 26 October 2026.

> Vesel connects straight to your Polar Loop over Bluetooth; once paired, the Loop talks only to Vesel.

## Intent
Read the band without the Polar app or Polar's cloud (decision `2026-10-26-no-cloud.md`).

## How it works
- The Loop pairs with one phone app only. To pair with Vesel it must be in factory state: remove it from Polar Flow / iOS Bluetooth settings, then factory reset it (reset button under the strap while on the charger). First open Polar Flow and sync once: the reset erases anything your Loop hasn't sent yet.
- Three steps: Before you start → Looking for the band (hold it within 1 m) → About you.
- Looking for the band scans for about 8 seconds and takes the strongest Loop in pairing mode. Problems: no Loop found (Keep looking or Cancel); the Loop didn't pair (factory reset instructions, Try again).
- iOS shows its own Bluetooth pairing prompt; accept it.
- About you: birth year, height, weight, sleep goal (5–11 h) and biological sex (Male / Female; the band's sleep and calorie maths need it). It stays on the band and the phone. Other first-time-setup values use Polar's defaults: max HR 220 − age, resting HR 60, VO2max from Polar's table, training "occasional", typical day "mostly sitting".
- Finish runs the band's first-time setup, stores the profile and the band, opens Today and runs the first sync (which sets the band's clock). If setup fails: "Setup didn't finish", Try again.
- Workouts (`workouts.md`): the first read after pairing switches on the Loop's automatic training detection, keeping its own sensitivity and shortest workout (else the SDK's 50 and 10 minutes). Forget this Loop resets this, so the next Loop gets it too.
- The VO2max default is the middle of the "Fair" band in Polar's table for your age group.
- Forget this Loop (Loop & settings): final sync, then factory reset of the band. If the final sync fails, a second confirm shows the time of the last read and that anything since then will be lost ("Reset anyway"). Health history on the phone stays. Remove "Polar Loop" from iOS Bluetooth settings afterwards. If the Loop can't be reached for the reset, Vesel forgets it anyway and says to reset it by hand.
- After forgetting, Polar Flow can pair again; Vesel then gets nothing.

## Changing About you later
- Units: the first About you row is a Metric / US switch (metric by default). US writes weight in lb, height in ft and in, waist in in, and skin temperature in °F; everything is stored metric. It saves at once in the phone's `setting` table (key `units`, not uploaded) and is never sent to the Loop. Pairing and the editor follow it: US shows Height as two fields, "ft" and "in", "Weight (lb)" and "Waist (in)". Every check runs on the metric value against the metric range (height 120–230 cm, weight 30–250 kg, waist 50–200 cm); the US words give bounds that convert inside them (4 ft 0 in – 7 ft 6 in, 67–551 lb, 20–78 in). A field left as it was keeps its stored metric number exactly; only an edited one is converted (lb ÷ 2.20462, in × 2.54, not rounded). So switching units, or opening the editor in US and pressing nothing, never writes the Loop.
- Body → About you: change height, weight, birth year, sex and sleep goal. Same fields and checks as pairing (`ProfileDraft`). The edit screen says: "Saving sends these to your Loop. Your Loop may take a few nights to settle its recovery again." Save stays off until something changed and every field is valid.
- Save waits for any running sync, then runs the band's first-time setup again (the only way the Polar SDK writes these; it rewrites the band's user file with the same identity and a new time), then stores them on the phone, which backs the profile up to the Mac again. Band first, then phone: `SyncPipeline.writeProfile` → `BandSync.firstTimeUse`. The live heart rate pauses while it writes and comes back after, also when it fails. It runs in background time ("Save to your Loop"); if iOS ends that time before the write starts, nothing is written or stored. Polar may restart its Nightly Recharge baselines afterwards; the owner accepted that.
- If the Loop doesn't take it: "Not saved. Your Loop didn't take the change, so nothing changed on your phone either. Keep the Loop close and try again." The edit stays on screen with Try again. The Loop may have taken part of it; trying again rewrites all of it.
- Worn on (Loop & settings): a Left / Right control, Left by default (Polar recommends the non-dominant hand). Choosing sends it to the Loop with `setUserDeviceLocation` (`WRIST_LEFT` / `WRIST_RIGHT`), then stores it in the phone's `setting` table (key `wrist`, not uploaded). Band first, then phone, like About you: `SyncPipeline.setWrist` waits for a running sync, and nothing is stored if the Loop refuses ("Not saved. Your Loop didn't take the change, so nothing changed on your phone either. Keep the Loop close and try again."; the control keeps showing the stored side). Pairing sends the stored side right after the Loop's first-time setup, so a re-pair keeps it; if that send fails, pairing still finishes and the Loop keeps its own default. Simulator: `-VeselFakeFailure wristFailed` makes the fake band refuse.
- A new birth year changes the exercise cut-off for stress on the last 3 days only (they are always recomputed); older days keep theirs.
- Simulator: `-VeselScreen aboutYou` opens the editor; `-VeselFakeFailure setupFailed` makes the fake band refuse.

## Do / Don't
- Do warn before pairing that Polar Flow stops syncing the band.
- Don't factory reset without a final sync attempt first.
