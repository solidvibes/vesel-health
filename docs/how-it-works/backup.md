# Mac backup

**Status:** Built. Checked with the real iPhone backing up to the owner's Mac.

> A copy of everything goes to your own Mac at home, over home Wi-Fi only.

## Intent
Backup and room for heavier analysis later, with no cloud in between (decisions `2026-10-26-mac-mini-server.md`, `2026-10-26-home-network-sync.md`).

## How it works
- Your Mac runs a small service on port 8443, one of two ways. It listens on whatever network the Mac is on; only a phone with the QR's key and certificate pin can use it. Never forward the port on your router.
  - **MacBook (or any Mac on macOS 27+):** the Vesel Backup menu bar app runs it while you're logged in, and opens at login.
  - **2014 Mac mini:** a background service started at boot, set up once in Terminal.
- Set up once: Pair phone in Vesel Backup (or the setup script on the Mac mini) shows a QR; scan it from Loop & settings. Both make the code with the same script and keep the backup in the same folder.
- The connection is encrypted; the phone only talks to the Mac whose certificate it saw in the QR, and sends a secret token kept in the iPhone's Keychain.
- The phone only takes a QR that names a home-network (`.local`) address, and never follows a redirect, so the token and the rows can't be sent anywhere else.
- After each sync, rows not yet backed up are sent in batches. If the Mac doesn't answer within 5 seconds (away from home, Mac off), they wait for the next sync.
- The phone never depends on the backup; everything on screen comes from the phone.
- The backup is one SQLite file on the Mac, in `~/Library/Application Support/vesel-server/` (not in an iCloud-synced folder).
- Remove backup deletes the token from the phone; the Mac's copy stays.
- No restore from the backup in v1.

## What is sent
- Every row of profile, sleep nights, Nightly Recharge, heart-rate, beat-to-beat and skin-temperature samples, activity days, the band's raw files, computed numbers and alerts that went out. Each row has its own key: the night, the day, the timestamp (a beat-to-beat session by its start), or kind/day for numbers and alerts.
- Not sent: the band's details, the band ledger, sync runs and settings. An alert still due at 07:00 waits until it has gone out (it may still be dropped).
- A row is sent again when it changes on the phone. A row marked as backed up is exactly one the Mac acknowledged and that hadn't changed since it was read.
- Deleted rows are not removed from the Mac: format v1 has no deletions. A computed number the phone drops (its input went away) stays in the backup as it last was; the phone's numbers can always be worked out again from the stored readings.
- Setting up against a Mac with a different certificate than before (a new Mac, or `setup.sh --force`) sends everything again; the Mac stores each row once, so resending is harmless.

## What Loop & settings shows
- Not set up: what the backup is and "Set up backup" (scan the QR). If the Mac didn't answer, showed another certificate or refused the key, nothing is kept and it says why.
- Set up: last backup time (also in the Sync card), how much is waiting, "Back up now", "Remove backup". Away from home it says the Mac didn't answer and backs up next time. If the Mac refuses the key or shows another certificate: "Scan the QR again".
- The backup runs last in every sync and never makes a sync fail. Its outcome is kept apart from the band syncs, so the widgets' "last read" only tracks the band.

## What the Vesel Backup menu shows
- An icon for on, off, not paired, or a problem.
- On or off, with a switch. Off: the phone keeps its rows until it's back on.
- The last backup and how many rows of each kind are stored (nights of sleep, heart-rate readings, …), read straight from the backup file.
- Pair phone / Pair again: the QR, on screen only, until the panel closes. Pair again makes a new key and keeps the certificate, so the phone re-scans and sends nothing again.
- Problems, each with one action: uv missing (copy `brew install uv`), port 8443 busy (how to fix), the server keeps stopping (try again, show the log).
- If the Terminal set-up is installed on that Mac, the app says so and starts nothing.

## Do / Don't
- Don't expose the service to the internet.
- Don't log what is uploaded, the token or the certificate (phone, server and Mac app). The token is on disk only as its hash.
- Uploads go only through `VeselSync.Uploader` with the pinned session.
