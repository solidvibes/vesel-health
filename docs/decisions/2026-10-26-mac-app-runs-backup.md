# A menu bar app runs the backup server on newer Macs; the Mac mini keeps the Terminal set-up

**Date:** 2026-10-26
**Who decided:** mine (the owner)
**Plan:** docs/plans/2026-10-26-mac-backup-app.md
**Supersedes:** Decision 4 of the iOS v1 phase 8 plan (launch daemon at boot), only for Macs that run the app. The launch daemon stays the way the 2014 Mac mini runs it.

## Context

Phase 8 runs the backup server as a launch daemon at boot, set up with a Terminal script and `sudo`. Once running it is invisible: no way to see it, switch it off or tell it's broken. The owner has this MacBook now and the 2014 Mac mini later; the Mac mini tops out at macOS 12 and can't run a current app.

## Decision

Keep both ways. On this MacBook and any newer Mac, a menu bar app, Vesel Backup, runs the existing Python server as its child process while it is open, and opens at login. The menu shows on/off and status, the last backup and how much is backed up per data type, pairs the phone by showing the QR on screen, and has an "Open at login" switch. On the Mac mini, the Terminal set-up (`server/setup.sh` + the launch daemon) stays as it is: headless, no menu.

Both ways make the certificate, token and QR with the same script (`setup.sh`; the app carries a copy and runs it) and use the same data folder. If the launch daemon is installed on a Mac, the app says so and stays out of its way.

## Why

The owner can see the backup on the MacBook, turn it on when they want, and not forget it, without Terminal. The Mac mini can't run the app, so it keeps what already works. One script for pairing means the two ways can't drift apart.

## Alternatives

Only the app: the Mac mini couldn't back up at all. Only the daemon: stays invisible on the MacBook. Keep the daemon and add a menu that only watches it: still `sudo` to install. Make the keys in Swift inside the app: two copies of the security-critical code to keep equal.

## What it means

- On the MacBook the server runs only while the owner is logged in and the app is open. When it sleeps or leaves home, the phone keeps its rows and catches up later.
- On the Mac mini the server starts at boot, as in phase 8.
- The upload format, the certificate pin, the token (stored only as its hash) and the data folder are the same on both; a phone set up on one way keeps working after switching a Mac to the other.
- One Mac runs one way, never both. The README says how to switch.
- The app needs uv (Homebrew) on the Mac; without it the menu says so and nothing starts.
- Adds a macOS app to the stack: Swift + SwiftUI `MenuBarExtra`, macOS 27, XcodeGen, in `mac/`.
- Reversing: drop `mac/`; the Terminal set-up still works on any Mac.
