# Alerts

**Status:** Built: stand-up reminders (`docs/plans/2026-10-29-sync-stays-fresh.md`, phase 3; not yet checked with the real Loop's alert), alerts, the morning sleep report, Today's "something's off" card and the Alerts switches in Loop & settings. The alerts and the morning report's tap are not yet checked on the real phone. "See what changed" opens the Recovery or Stress page for today.

> Vesel speaks up only when something has been off for a while.

## Intent
Tell, don't make you look; never nag (decision `2026-10-26-background-alerts.md`).

## How it works

| Alert | Fires when | Default |
|---|---|---|
| Low recovery | Nightly Recharge poor or very poor (2 of 6 or lower) two nights running, or HRV more than 2 SD below your usual two nights running | On |
| Unusual resting HR | Resting HR more than 2 SD above your usual two nights running, or more than 3 SD once | On |
| Long high stress | 45 or more high-stress minutes within any 2 hours today (needs stress past its 7 learning days) | On |
| Morning sleep report | "Slept 7 h 12 m · Recharge OK", once per night, when last night's sleep and Nightly Recharge are both stored | On (since phase 2 of `docs/plans/2026-10-30-calmer-morning.md`; database migration v6 reset a stored value once so it follows the new default) |
| Stand-up reminders | The Loop's own inactivity alert fires (it must be on in the band's settings, set in Polar Flow; Vesel can't read or change it). "Time to move" / "Your Loop says you've been still for a while." No sound, nothing 22:00–07:00, dropped if it reaches the phone more than 5 minutes late, the newest replaces the last, not stored in `alert_event`, never on Today. An opt-in exception to "never nag" (`2026-10-29-stand-up-reminders.md`) | Off |

- Stand-up reminders aren't worked out from your numbers: the reminder arrives with the Loop's notice, beside any read, never behind one. The notice also wakes a read, like any check-in (`band-sync.md`).
- Worked out on the phone after every sync (`alerts`, version 1), only from today's numbers: a night has to be last night, a stress number today's.
- Quiet rules: no alert before 7 earlier nights; at most one per kind per day; one run of nights alerts once (a third poor night in a row stays quiet); for low recovery, a run of poor Nightly Recharge and a run of low HRV that overlap count as one.
- Nothing 22:00–07:00. Found between midnight and 07:00, it waits for 07:00 and every sync before then checks it again; if it no longer holds, it's dropped. Found between 22:00 and midnight, it isn't sent: by morning it's about yesterday. Nothing real is lost: if a recovery or resting-heart-rate run still holds the next night, that morning's own check sends it (the late evening stored nothing, so the run hasn't alerted yet); if it doesn't hold, a 07:00 re-check would have dropped it anyway. A stress stretch is about its own day only.
- Local notifications from the phone; works without the Mac mini or internet. iOS asks once for permission: at the end of pairing, the first time a switch is turned on, or on the first open after this update.
- Tapping the morning sleep report opens that night's Sleep page on D; any other notification opens Today. Each notification's id is `alert.<kind>.<night>` (`AlertIdentifier`), and the tap goes where the id says. Today shows "something's off": the alert card under the Heart rate card, a warm glow behind, and "See what changed" (the Recovery page for recovery and resting heart rate, the Stress page for stress).
- Every alert stores what fired, when, its text and why (its inputs and a sentence), in `alert_event`.
- Switches live in Loop & settings → Alerts, stored on the phone.

## Do / Don't
- Don't alert on a single bad night.
- Don't send anything through a push server.
- Don't log a notification's text.
