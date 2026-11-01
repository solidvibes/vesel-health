# Storage problems

**Status:** Built: the recovery screen and background retries at launch, and the read card on screens. Not yet checked on the iPhone. Plan: `docs/plans/2026-10-31-exemplar-polish.md` (phases C1 and C3).

> When Vesel can't open or read your data, it says so calmly and lets you try again. It never deletes anything to get going.

## Intent
Today a database that won't open closes the app, and a read that fails leaves a grey placeholder forever. Neither tells you anything. Your data is almost always still there, so the app should say that.

## How it works
- **Can't open the data at launch** → a full screen instead of the tabs, one of three:
  - Saved by a newer Vesel: "Vesel needs an update". No button; install the newer version.
  - Couldn't open right now (for example before the phone's first unlock): "Vesel can't open your data right now", with Try again.
  - Build set up wrong (no shared data folder): "Vesel isn't set up right", pointing to the README.
- Background work (band events, refresh, the long read, the Shortcut) skips quietly while the data can't be opened. The Shortcut says "Open Vesel first."
- Vesel tries again by itself when the iPhone is unlocked for the first time after a restart, and whenever it comes to the front. When it succeeds in the background, it carries on as usual (connects to the Loop, listens for its events).
- **A read fails on a screen** → one "Couldn't show this" card in place of the placeholder, with Try again. One per screen, never one per section.
- A database paused because Vesel is in the background is not a problem: no card.
- Units, the first day with data and the Loop button's battery keep their last value and try again the next time Vesel comes to the front. No card.
- No error codes or technical text on screen, and none in logs.

## Do / Don't
- Never offer to delete, reset or re-create the data from these screens.
- Never show the card for something that fixes itself when the app comes back to the front.
