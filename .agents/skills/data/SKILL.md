---
name: data
description: Use when a change reads, stores, uploads or deletes health data, touches the database schema, or adds any network call.
---

# Data

- The phone's SQLite database (VeselStorage) is the source of truth. Screens, widgets and alerts read from it, never from the band or the server.
- Health data leaves the phone only to the owner's own Mac, over the pinned HTTPS connection. Any other destination needs a new decision first.
- Uploads go only through `VeselSync.Uploader` with `PinnedSession` (public-key pin from the set-up QR, token from the Keychain). A row is marked uploaded only when the Mac acknowledged it unchanged. The server never logs bodies or tokens.
- `server/setup.sh` is the only code that makes the certificate and token. The Vesel Backup Mac app runs it (`--qr-text`) and never logs, stores, or copies the token or QR; only `token.sha256` is on disk. The app reads the backup file only for counts, and never writes to it.
- No analytics, crash reporting or third-party SDKs that send data. The Polar BLE SDK talks only to the band.
- Two kinds of stored data, kept apart: band readings (their own tables, kept as they came) and numbers worked out from them (`computed_metric`, each with a method and version). A worked-out number is never the only copy of anything: it can always be rebuilt from the readings, and is recomputed when its method changes or late readings arrive.
- Late readings are found through `band_ledger.stored_at` later than the day's numbers.
- A series worked out on read selects only the columns it needs (never `uploaded_at`) and groups off the main thread.
- Schema changes are GRDB migrations; never edit a shipped migration.
- Delete data from the band only after it is safely in the database. Clearing goes through `ClearPlan` and `band_ledger`, per band data type; never today or yesterday. An empty day counts as stored only after two empty reads once the day has ended, an hour apart (the SDK reports some failed reads as empty).
- Readings with data are stored as each kind arrives. Empty days, heart-rate and beat-to-beat ledger rows, and clearing only after a whole read: every fetch returned, not cancelled, no Bluetooth drop (`WearableSource.drops`). The Polar SDK reports a failed file as no data.
- A stored day with data is never replaced by an empty re-fetch (the band returns nothing for days it has cleared).
- A waiting "I'm up" (`ImUpRequest`) is delivered by `SyncPipeline` before a read, only while under 6 hours old and last night isn't stored; no ordinary read ends sleep without one. Ending the night from Vesel stamps `nightEnded(at:)`.
- The connection log (`band_link`) holds times and link words only, kept 14 days, never uploaded.
- Never log heart-rate, sleep or any health values, tokens or certificates.
- Real recordings stay in `ios/LocalFixtures/`; agents are denied reading it (`.claude/settings.json`).
- Sync log words come from `SyncRunWords`; `sync_run.detail` is written from `SyncDetail` constants and never shown as it is.
- The database is excluded from device backups (iCloud) and opened with GRDB's shared-database setup.
- The App Group id comes from `VESEL_BUNDLE_PREFIX` via Info.plist (`VeselAppGroup`); never hard-code it.
- Notification text is built from `Alert` only (VeselCore); never log it. Notifications are local, never through a push server.
- A notification's id is `AlertIdentifier` (VeselCore); its tap goes where the id says.
- Display units come from the `units` setting (`setting` table, not uploaded); stored values and explanation texts stay metric.
- Live heart rate is display-only, via `LiveHeartRateController`; never stored or logged.
- Every background entry point (band event, refresh, background time) resumes the database first and suspends it when it finishes and in its expiration handler. The long read and the continued read (Sync now and I'm up after you leave) do this through `BackgroundTime.hold`, outside `beginBackgroundTask`.
