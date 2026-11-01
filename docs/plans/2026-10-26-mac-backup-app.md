---
status: Implemented 2026-10-26
---

# Vesel Backup: a menu bar app that runs the backup server
**Date**: 2026-10-26
**Status**: Implemented 2026-10-26
**Touches**: `docs/how-it-works/backup.md`, `docs/stack.md` (Server row, new Mac app row, code layout), `docs/intent.md` and `AGENTS.md` ("Mac mini" → the owner's own Mac), `AGENTS.md` (Factory `layers`, `checks`, `codegen`, `run`, `ships`), `server/README.md`, `.agents/skills/data/SKILL.md`, `.agents/skills/layers/SKILL.md`, `docs/decisions/2026-10-26-mac-app-runs-backup.md`

Needs iOS v1 phase 8 merged: this builds on its server, QR and phone half.

## TL;DR
- Two ways to run the backup server, one contract: the new menu bar app (this MacBook, any newer Mac) and the existing Terminal set-up (2014 Mac mini, macOS 12, headless).
- New `mac/`: "Vesel Backup", a SwiftUI `MenuBarExtra` app (macOS 27, XcodeGen, the builder's team (`Signing.local.xcconfig`)), no Dock icon.
- It runs the existing FastAPI server as its child process while it's open; opens at login via `SMAppService.mainApp`.
- `server/setup.sh` and `server/launchd/` stay for the Mac mini. `setup.sh` gains `--qr-text`; the app runs that bundled copy to pair.
- One pairing implementation (`setup.sh`): certificate, token, hash, QR are identical on both ways by construction.
- New `server/tests/test_setup.py` checks `setup.sh`'s output against the README contract, with `/usr/bin/openssl` (the app's) and the PATH one.
- Server code and `setup.sh` copied into the app at build time; `uv sync` makes a venv in the data folder; the app runs that Python directly.
- Same data folder for both: `~/Library/Application Support/vesel-server/`.
- Launch daemon installed (`/Library/LaunchDaemons/app.vesel.server.plist`) → the app explains "the Terminal set-up runs the backup here", starts nothing, never pairs.
- QR rendered with Core Image in the menu panel, in memory only; closing the panel drops it.
- "Pair again" = new token, certificate and pin kept, so the phone re-scans but sends nothing again.
- Menu: on/off, status, last backup, counts per data type (read-only GRDB), Pair phone, Open at login, Quit.
- Upload format v1, storage, pin + token, 600/700 permissions: unchanged. No server code change.
- Contract: `checks.fast` adds the kit's `swift test`; `checks.full` adds the Mac build; `run`, `codegen`, `ships`, `layers` gain the Mac app.

## Context
The owner wants to see the backup server, turn it on when they want, and not forget it. Today it is a Terminal script plus a launch daemon installed with `sudo` (phase 8, Decision 4), invisible once running. The owner has this MacBook (macOS 27.0.1) now and a 2014 Mac mini later. The Mac mini tops out at macOS 12 and can't run a macOS 27 app, so it keeps the Terminal set-up, headless, no menu. Owner: "Keep both ways."

Checked on this Mac: no `~/Library/Application Support/vesel-server/`, no `/Library/LaunchDaemons/app.vesel.server.plist` (setup never ran); uv 0.6.9 at `/opt/homebrew/bin/uv` with a uv-managed CPython 3.12.9; `/usr/bin/openssl` is LibreSSL 3.3.6, PATH `openssl` is Homebrew OpenSSL 4.0.3; qrencode installed; application firewall off; Xcode 27.1, XcodeGen 2.46.0.

## Constraints
- Rules: `AGENTS.md`, `.agents/skills/data/SKILL.md` (network, tokens, never log values), `.agents/skills/layers/SKILL.md` (new module boundaries), `.agents/skills/testing/SKILL.md` (Swift Testing, pytest for server code, injected clock).
- Invariants: health data goes only phone → the owner's Mac over the pinned connection; never log tokens, bodies, health values or the QR; every number on the menu explainable (counts are row counts straight from the backup file).
- Contract unchanged from phase 8 (Decisions 1–2), and identical on both ways: upload format v1, generic `row` storage, SPKI SHA-256 pin + bearer token, QR `vesel-backup://<LocalHostName>.local:8443?token=<base64url 43>&pin=<base64 %-encoded>`, token stored only as lowercase hex SHA-256 in `token.sha256`, data in `~/Library/Application Support/vesel-server/`, files 600, dirs 700. Exact rules: `server/README.md` "For the phone half".
- Risk areas touched: **the phone ↔ Mac connection (certificate, token)**, **secrets** (private key, token). Not touched: what the phone sends, migrations, band.
- Packs: none (`docs/stack.md` has no `## Packs`).

## Approach

### Two ways, one contract (agent's decision)
| | Menu bar app | Terminal set-up |
|---|---|---|
| For | this MacBook, any Mac on macOS 27+ | 2014 Mac mini (macOS 12), headless |
| Pairing | runs its bundled `setup.sh --qr-text`, shows the QR | `setup.sh`, QR in Terminal |
| Runs the server | child process while logged in | launch daemon at boot (`server/launchd/`) |
| Data folder | `~/Library/Application Support/vesel-server/` | same |

Kept in step by having **one** pairing implementation: `setup.sh`. The app carries a copy and runs it; it never makes keys itself. `server/tests/test_setup.py` pins `setup.sh` to the README contract. The uvicorn arguments exist twice (plist, `ServerLaunch`); a kit test reads `server/launchd/app.vesel.server.plist` and compares the uvicorn arguments after `uvicorn`.
- Ruled out: pairing in Swift (CryptoKit + swift-certificates) plus a parity test against `setup.sh` (two implementations of the risk-area code to keep equal forever, and a new dependency); moving pairing into Python (`cryptography` dependency, rewrites a working script).
- One Mac never runs both. The app detects the daemon and stands aside (see below); the README says pick one per Mac.

### `setup.sh --qr-text`
New flag, used by the app and by `test_setup.py`. Everything else in `setup.sh` is unchanged (default run and `--force` behave as today).
- Keeps `certs/cert.pem` + `key.pem` when both exist; otherwise makes both (same `openssl` commands as today).
- Always makes a new token and `token.sha256`. No "already exists" refusal.
- Needs only `openssl` and `shasum` (no qrencode, no uv): skips `uv sync`, the plist render and all the Terminal text.
- stdout: exactly one line, the QR text. Errors to stderr, exit ≠ 0. stderr never carries the token (it only names tools and paths).
- `--qr-text` with `--force` → usage error.

### Where the app lives and how it's built
```
mac/
  project.yml                 XcodeGen: app target VeselBackup, macOS 27.0, Swift 6, the builder's team (`Signing.local.xcconfig`), Automatic signing
  VeselBackup/                app target: menu, pairing panel, server controller
  Packages/VeselBackupKit/    pure logic, tested with `swift test` (macOS 27)
```
- Bundle id `app.vesel.backup`, product name "Vesel Backup", `LSUIElement = YES`, `NSLocalNetworkUsageDescription`. App Sandbox off (it spawns Python and owns a folder outside its container); no hardened runtime or notarization (built and run on the owner's Macs only).
- A pre-build script rsyncs `server/pyproject.toml`, `uv.lock`, `.python-version`, `setup.sh` and `vesel_server/` (excluding `__pycache__`, `.venv`, `tests`) into `Contents/Resources/server`. The app always carries the server and script it was built with; updating = rebuild and reinstall. Target sets `ENABLE_USER_SCRIPT_SANDBOXING: NO` for that script.
- Install on this Mac: Release build, `ditto` into `/Applications/Vesel Backup.app`, open it. `SMAppService.mainApp` wants the app in `/Applications`.

### Running the server
"The Mac app carries the backup server inside it and uses uv, already on this Mac, to give it its own Python." Every child process gets an environment built from scratch: `HOME`, `PATH=/usr/bin:/bin:/usr/sbin:/sbin`, `VESEL_SERVER_HOME=<data>`, plus per process below. Nothing else inherited. Start, in order:
1. **Daemon check.** `/Library/LaunchDaemons/app.vesel.server.plist` exists → state `terminalSetup`: "The Terminal set-up runs the backup on this Mac." with "How to switch" (opens the README section). Nothing starts, nothing is killed, no pairing; switch and Pair hidden; last backup and counts still shown (same folder, read-only).
2. **uv.** Look at `/opt/homebrew/bin/uv`, `/usr/local/bin/uv`, `~/.local/bin/uv`, `~/.cargo/bin/uv` (a GUI app has no shell `PATH`). None → `problem(.uvMissing)`: "Needs uv to run. Install it with Homebrew: brew install uv", with a Copy button.
3. **Sync.** `uv sync --frozen --no-dev --project <Resources/server>` with `UV_PROJECT_ENVIRONMENT=<data>/venv`. No-op when synced; the first time it may fetch Python and packages from the internet (not health data). State `starting` ("Getting ready…"), timeout 5 min; failure → `problem(.keepsStopping)` path with "Show log" (uv's stderr appends to `server.log`).
4. **Port.** If `127.0.0.1:8443` accepts a TCP connection: a pid in `server.pid` that is alive and whose executable (`proc_pidpath`) equals the resolved path (`realpath`) of `<data>/venv/bin/python` is our orphan from a crash → SIGTERM, wait 3 s, continue. Otherwise `problem(.portBusy)`.
5. **Spawn** `<data>/venv/bin/python -m uvicorn vesel_server.app:create_app --factory --app-dir <Resources/server> --host 0.0.0.0 --port 8443 --ssl-certfile <data>/certs/cert.pem --ssl-keyfile <data>/certs/key.pem --no-access-log --no-server-header` with `PYTHONDONTWRITEBYTECODE=1` (never write into the signed bundle). Python is the direct child, so one signal stops it. stdout and stderr append to `<data>/server.log` (600); the server logs only method, path, status, row count (`tests/test_logging.py`). Write `<data>/server.pid`.
6. **Ready** when `127.0.0.1:8443` accepts a TCP connection (poll 0.5 s, up to 20 s) → `on`.
- The app calls `umask(0o077)` at launch, so everything it and its children create is 600/700 (like the plist's `Umask 63`). Every start re-applies 700/600 to the known paths.
- Unexpected exit → restart after 5 s; the third exit within 10 minutes → `problem(.keepsStopping)` with "Try again" and "Show log" (reveals `server.log` in Finder).
- Off switch or Quit → SIGTERM, wait up to 3 s, then SIGKILL; remove `server.pid`.
- Ruled out: bundling the uv binary (re-signing a Homebrew binary inside the app); running through `uv run` (uv stays the parent and signal forwarding is its business); a launch agent (owner chose the app runs it); rewriting the server in Swift (stack.md keeps Python, and the phase 8 tests stay valid).

### Pairing (risk area: certificate, token, secrets)
- "Pair phone" (not paired) and "Pair again" (paired; confirm first: "Your iPhone stops backing up until it scans the new code") do the same: run `/bin/bash <Resources/server/setup.sh> --qr-text` with the environment above (Debug test runs add `VESEL_SERVER_HOST`), read its stdout into memory, restart the server (it reads `token.sha256` once at start), show the QR.
- Before rendering, `PairingCode.parse` (kit) checks the line: scheme `vesel-backup`, port 8443, token 43 base64url chars, pin present. Anything else → "Couldn't make a pairing code" plus setup.sh's last stderr line; nothing shown.
- The certificate and pin stay across re-pairs, so the phone keeps its upload marks and sends nothing again.
- The token exists only in the pipe, the pairing view's state and the rendered `CGImage`; closing the panel or "Done" drops them. Never logged, never written, never on the pasteboard. An old QR can't be shown again (only the hash is kept); that's why every pairing makes a new token.
- "Paired" = `certs/cert.pem`, `certs/key.pem` and `token.sha256` all exist.
- Host shown in the menu: `SCDynamicStoreCopyLocalHostName` + `.local` (display only; `setup.sh` picks the certificate's host itself with `scutil`).

### The menu (MenuBarExtra, `.window` style)
State: `notPaired | off | starting | on | problem(Problem) | terminalSetup`. Icons (template SF Symbols, implementer confirms the names exist): on `externaldrive.badge.checkmark`, off `externaldrive`, problem and terminalSetup `externaldrive.badge.exclamationmark`, not paired `externaldrive.badge.plus`; `starting` uses the on icon.
- Header: "Vesel Backup" and one status line: "On · <host>.local", "Off · your iPhone keeps its rows until it's back on", "Getting ready…", the problem sentence, "The Terminal set-up runs the backup on this Mac.", or "Not paired yet".
- Switch "Backup server" (hidden when not paired or terminalSetup). Remembered in `UserDefaults` (`serverOn`, default true); at launch the app restores it.
- Last backup: `MAX(received_at)`, relative ("today 07:42"). Counts from `SELECT table_name, COUNT(*) FROM row GROUP BY table_name`, read when the panel opens, off the main thread, with GRDB `Configuration.readonly = true` (never creates, never migrates). Labels: `sleep_night` nights of sleep · `nightly_recharge` Nightly Recharge nights · `hr_sample` heart-rate readings · `ppi_sample` beat-to-beat readings · `skin_temp_sample` skin temperature readings · `activity_day` days of activity · `alert_event` alerts · everything else summed as "other rows". No file yet or zero rows → "Nothing backed up yet". The server uses WAL and closes after each request, so the file is often there without `-wal`/`-shm`; that case must read fine.
- "Pair phone…" / "Pair again…" → the panel swaps to the pairing view: QR (Core Image `CIQRCodeGenerator`, level M, nearest-neighbour scaled, 220 pt), "On your iPhone: Vesel › Loop & settings › Set up backup, then scan this." and "This code is the key to your backup. Don't photograph or share it." Button "Done".
- Switch "Open at login": `SMAppService.mainApp.register()/unregister()`, reflecting `.status`. On first launch the app registers once (flag in `UserDefaults`), except in Debug test runs (`-VeselServerHome` given). `.requiresApproval` → "Allow it in System Settings › General › Login Items" with a button to `SMAppService.openSystemSettingsLoginItems()`.
- Problem rows add one action: uv missing → Copy `brew install uv`; port busy → "How to fix" opens the README section; keeps stopping → "Try again", "Show log".
- "Quit Vesel Backup" (stops the server first).

### Code shape
- `VeselBackupKit` (no UI, no `Process`): `ServerHome` (paths, paired check, permission sweep), `PairingCode` (parse and check the QR line), `BackupStats` (read-only counts + last received), `UVLocator`, `ServerLaunch` (sync, setup and uvicorn argument/environment builders), `DaemonCheck` (plist path → installed?), `MenuLabels` (table → label). Dependency: GRDB 7.11+ (as in `ios/Packages/VeselStorage`).
- App target: `VeselBackupApp.swift` (MenuBarExtra, icon from state, `umask`), `ServerController.swift` (`@MainActor @Observable`: state machine, `Process`, pid file, restart policy, port probe, runs `setup.sh --qr-text`), `MenuView.swift`, `PairingView.swift`, `LoginItem.swift`.
- Debug-only launch arguments: `-VeselServerHome <dir>`, `-VeselServerHost <name>` (e.g. `localhost`, passed to `setup.sh` as `VESEL_SERVER_HOST`), `-VeselDaemonPlist <path>` (stands in for the daemon plist path); ignored in Release.

### Phone copy
Two strings in `ios/Vesel/Loop/BackupSection.swift` ("Run setup.sh --force on the Mac mini…", "Scan the one setup.sh shows…") and one doc comment in `ios/Packages/VeselSync/Sources/VeselSync/Backup.swift` name only `setup.sh`. They become: "Make a new code on your Mac (Pair again in Vesel Backup, or setup.sh --force on the Mac mini) and scan it." / "Scan the code Vesel Backup or setup.sh shows on your Mac." Other "Mac mini" wording on the phone stays.

## Files
- `mac/project.yml` — XcodeGen spec (app target, Info.plist keys, GRDB via the kit, copy-server script).
- `mac/VeselBackup/VeselBackupApp.swift` — `@main`, `MenuBarExtra`, icon by state, `umask` at launch.
- `mac/VeselBackup/ServerController.swift` — daemon check, uv, sync, port/orphan, spawn, probe, pid file, restarts, pairing run.
- `mac/VeselBackup/MenuView.swift` — status, switch, last backup, counts, actions.
- `mac/VeselBackup/PairingView.swift` — QR panel, confirm-before-re-pair.
- `mac/VeselBackup/LoginItem.swift` — `SMAppService.mainApp` wrapper.
- `mac/VeselBackup/Assets.xcassets` — app icon only.
- `mac/Packages/VeselBackupKit/Package.swift` — macOS 27, GRDB.
- `mac/Packages/VeselBackupKit/Sources/VeselBackupKit/ServerHome.swift`, `PairingCode.swift`, `BackupStats.swift`, `UVLocator.swift`, `ServerLaunch.swift`, `DaemonCheck.swift`, `MenuLabels.swift`.
- `mac/Packages/VeselBackupKit/Tests/VeselBackupKitTests/PairingCodeTests.swift`, `BackupStatsTests.swift`, `ServerLaunchTests.swift`, `ServerHomeTests.swift`, `UVLocatorTests.swift`.
- `server/setup.sh` — `--qr-text` flag (and the usage comment).
- `server/tests/test_setup.py` — runs `setup.sh --qr-text` into temp folders, checks the contract.
- `server/README.md` — "Two ways to run it": Vesel Backup app (newer Mac) and the existing Terminal steps (Mac mini); pick one per Mac; switching from the daemon to the app (`sudo launchctl bootout system/app.vesel.server`, `sudo rm /Library/LaunchDaemons/app.vesel.server.plist`, same data folder, phone keeps working). Phone-half contract unchanged.
- `ios/Vesel/Loop/BackupSection.swift`, `ios/Packages/VeselSync/Sources/VeselSync/Backup.swift` — `setup.sh` wording.
- `.gitignore` — `mac/VeselBackup.xcodeproj/`, `mac/build/`, `mac/VeselBackup/Info.plist` if generated.
- `AGENTS.md` — Factory `layers`, `checks`, `codegen`, `run`, `ships` (see Verification); non-negotiable "the owner's own Mac mini" → "the owner's own Mac (the Mac mini or the MacBook)".
- `docs/intent.md` — the same wording: the backup Mac is the owner's own Mac (MacBook now, 2014 Mac mini later). Follows Decision 1; no other change.
- `docs/stack.md` — Server row ("run by the Vesel Backup menu bar app on a newer Mac, or a launch daemon on the 2014 Mac mini"), new "Mac app" row, `mac/` in code layout.
- `docs/how-it-works/backup.md` — the Mac side: both ways, menu, pairing, on/off. Not marked Planned now: another agent is editing that file on this branch; `go` updates it when the code lands.
- `.agents/skills/data/SKILL.md`, `.agents/skills/layers/SKILL.md` — see Rule gaps (when the code lands).
- `docs/decisions/2026-10-26-mac-app-runs-backup.md` — drafted with this plan.
- `CHANGELOG.md` — one line.

## Steps
- [x] 1. `server/setup.sh --qr-text` and `server/tests/test_setup.py`; `cd server && uv run pytest` green.
- [x] 2. `VeselBackupKit`: `ServerHome`, `PairingCode`, `BackupStats`, `UVLocator`, `ServerLaunch`, `DaemonCheck`, `MenuLabels` with tests; `swift test` green.
- [x] 3. `mac/project.yml`, app shell (`MenuBarExtra`, `umask`, copy-server script); builds, shows an icon, `Contents/Resources/server/setup.sh` is in the bundle.
- [x] 4. `ServerController`: daemon check, uv, sync, port/orphan, spawn, probe, restarts, stop on off/quit, pairing run; all states.
- [x] 5. `MenuView`, `PairingView`, `LoginItem`.
- [x] 6. README, phone strings, `.gitignore`, `stack.md`, `intent.md`, `backup.md`, `AGENTS.md` (contract + wording), skills, CHANGELOG. Local end-to-end on this Mac (see Verification), then a Release install to `/Applications` (owner's go: left to the orchestrator with the owner).
- [ ] 7. **Owner-only:** Owner pairs the real iPhone.

## Decisions
1. **mine** — The menu bar app runs the backup server as its child process while it is open, and opens at login, on this MacBook and any newer Mac. Supersedes phase 8 Decision 4 for those Macs only.
2. **mine** — The menu shows on/off and status (icon for on / off / problem), last backup time and counts per data type from the server's SQLite, "Pair phone" with the QR on screen, and an "Open at login" switch.
3. **mine** — Keep both ways. The Terminal set-up (`server/setup.sh` + `server/launchd/`) stays for the 2014 Mac mini (macOS 12 max), headless, no menu. Both produce the same certificate, token, pin and QR and use the same data folder; the app detects an installed launch daemon and explains it instead of fighting it; the README documents both.
4. **agent's, hard to undo** — `setup.sh` is the only pairing implementation. The app bundles it and runs `setup.sh --qr-text`; it never makes keys in Swift. `test_setup.py` checks the output against the README contract with both openssl builds. No swift-certificates dependency.
5. **agent's** — Server code is bundled into the app at build time; uv (Homebrew) makes a venv in the data folder; the app runs that Python directly. uv missing = a problem state with the install line.
6. **agent's** — Every pairing in the app makes a new token; the certificate and pin stay unless missing, so re-pairing never resends the phone's data. (The Terminal `--force` keeps replacing both, as today.)
7. **agent's** — The QR exists only on screen, in the menu panel, until it closes.
8. **agent's** — Counts are read straight from the backup file, read-only; no new server endpoint (format v1 unchanged).
9. **agent's** — Daemon installed (plist present) → the app stands aside: explains, starts nothing, never pairs, still shows counts. No admin-prompt code; switching steps in the README.
10. **agent's** — Lives in `mac/` with its own XcodeGen project and package, macOS 27, bundle id `app.vesel.backup`, not sandboxed.

## Deviations
- `setup.sh --qr-text` exactly as planned; LibreSSL 3.3.6 (`/usr/bin/openssl`) and Homebrew OpenSSL 4.0.3 both pass `test_setup.py` (parametrised on PATH). The test copies `setup.sh` into a temp folder, so "no plist, no `.venv`" is checked on the script's own folder.
- `BackupStats` doesn't use `Configuration.readonly`: SQLite's read-only open fails (error 14) on a WAL file whose `-shm` is gone, exactly the server's state between requests. It opens only an existing file, read-write with `PRAGMA query_only = 1`, so it still never creates, writes or migrates. macOS's SQLite keeps `-wal`/`-shm` after a read; harmless, 600 by the umask.
- Extra kit file `RestartPolicy.swift` (+ test): the "third exit within 10 minutes" rule with an injected time. Extra app file `AppConfig.swift`: paths and the Debug launch arguments.
- Debug test runs (`-VeselServerHome`) keep settings in a separate defaults suite (`app.vesel.backup.testrun`), so a test run never flips the real install's on/off; "Open at login" is disabled in them and never registered.
- Pairing turns the server switch on (the phone's scan needs the server answering).
- "Pair again" confirms inline in the panel (an alert from a menu bar panel is unreliable). The QR view is dropped on `Done`, when the panel disappears, and when its window resigns key.
- Quit and logout go through `applicationShouldTerminate` → stop the server (SIGTERM, 3 s, SIGKILL) → quit.
- `--app-dir <bundled server>` goes after the shared uvicorn arguments, so the kit test compares the plist's list verbatim.
- Phone copy: three strings named `setup.sh` (not two); all three updated.
- `AGENTS.md` risk line now says "phone ↔ Mac connection" (was "Mac mini"); same meaning.
- Screenshots: no screen-recording or Accessibility permission here, so the real menu bar can't be opened or captured. A non-hosted test target `VeselBackupSnapshots` renders the real `MenuView`/`PairingView` offscreen (`NSHostingView.cacheDisplay`), only when `TEST_RUNNER_VESEL_SHOTS*` is set (skipped otherwise). `pair` mode drives the real `ServerController.pair()` (bundled-equivalent `setup.sh`, scratch home); `states` mode sets the state directly. In the offscreen window switches draw inactive; the Off shot's switch shows the stored "on".
- End-to-end, this Mac (Debug app, scratch home, host `localhost`): pairing via the snapshot test, QR decoded from its PNG with `CIDetector`; the app ran `uv sync` into `<home>/venv` and served; the Simulator app took `-VeselBackupQR` and uploaded 28 342 rows in 63 batches; the menu render read those counts. Pair again (the bundled `setup.sh --qr-text`, same pin, new token) + killing the server: the app restarted it in 5 s with the new token; the phone's old token got 401; the new QR gave only `GET /v1/status` (nothing re-sent). `kill -9` of the app left an orphan; the relaunch replaced it (one server). Quit (Apple event) stopped the server and removed `server.pid`. Off at launch and port held by `nc -l 8443`: no server started. No token in `server.log`, the data folder, the app's stdout, the prefs or the unified log; permissions 700/600; no `__pycache__` in the bundle; no login item (checked once with `sfltool dumpbtm`, 0 entries; not to be repeated, it prompts the owner).
- Not run here (owner's go): the Release install to `/Applications`, the first real pairing.
- Security review: the orphan check also needs the process to have started before `server.pid` was written (`proc_pidinfo`), since the venv's Python resolves to uv's shared interpreter and a reused pid could be any uv Python. Child environments add `TMPDIR` (the per-user temp folder), so `setup.sh`'s new key never sits in `/tmp`. "Open at login" works in Release builds only; a Debug build never registers (an earlier Debug run without `-VeselServerHome` had set `loginItemOffered`). A pairing code that arrives after the panel closed is dropped, not shown later.

## Verification
Contract changes (applied in step 6):
- `checks.fast` adds `&& swift test --package-path mac/Packages/VeselBackupKit`.
- `checks.full` adds `cd mac && xcodegen generate && xcodebuild build -project VeselBackup.xcodeproj -scheme VeselBackup -destination 'platform=macOS' -quiet` (from the repo root); `cd server && uv run pytest` stays and now covers `setup.sh`.
- `codegen` adds `mac/project.yml → cd mac && xcodegen generate`.
- `run` adds the Mac app: `cd mac && xcodegen generate && xcodebuild -project VeselBackup.xcodeproj -scheme VeselBackup -configuration Debug -derivedDataPath build build && "build/Build/Products/Debug/Vesel Backup.app/Contents/MacOS/Vesel Backup" -VeselServerHome <scratch dir> -VeselServerHost localhost` (add `-VeselDaemonPlist <file>` for the Terminal-set-up state); screenshot with `screencapture`. Install for the owner: the same with `-configuration Release`, then `ditto` into `/Applications` and `open`.
- `ships` becomes: iOS (owner's iPhone only), macOS menu bar app with the server (owner's MacBook), server via Terminal set-up (Mac mini at home).
- `layers` adds: mac: menu (SwiftUI) → `ServerController` → `VeselBackupKit` → bundled `setup.sh` / server process (uvicorn) / backup SQLite (read-only).

Checks:
- [x] `checks.full` green (kit tests, Mac build, iOS tests, pytest).
- [x] `test_setup.py`, run once with `PATH=/usr/bin:/bin:/usr/sbin:/sbin` (LibreSSL, the app's) and once with the test's own PATH (Homebrew OpenSSL here), `VESEL_SERVER_HOST=localhost`: stdout is one line; token 43 base64url chars; `token.sha256` is its lowercase hex SHA-256; pin equals the README's `openssl x509 … | openssl pkey … | openssl dgst … | base64` on `cert.pem`; `+ / =` percent-encoded and `urllib.parse` gives back pin and token; certificate has SAN `DNS:localhost`, CA:FALSE, serverAuth, ~3650 days; files 600, folders 700; a second `--qr-text` keeps `cert.pem` (same pin) and changes the token; no plist or `.venv` written; `--qr-text --force` exits ≠ 0. Then `create_app` with that folder accepts the printed token on `GET /v1/status` (TestClient) and refuses the first run's token.
- [x] Kit tests: `PairingCode` accepts a real `setup.sh` line and rejects wrong scheme, port, short token, missing pin; `BackupStats` on a temp SQLite with the server's `row` table gives the right counts and last time, also on a WAL file whose writer closed (no `-wal`/`-shm`), and a missing file gives "nothing yet"; uvicorn arguments equal those after `uvicorn` in `server/launchd/app.vesel.server.plist`; each environment holds only the listed keys; `DaemonCheck` true for an existing temp file, false otherwise; `ServerHome` paired only when all three files exist and the sweep sets 700/600.
- [x] Local end-to-end (Debug, scratch home, host `localhost`): not paired → Pair phone shows a QR; decode the screenshot's QR (Core Image `CIDetector`, scratch script), launch the Simulator app with `-VeselBackupQR <text>`; rows arrive; the menu shows counts and last backup; Pair again → the old phone token gets 401 ("Scan the QR again"), scanning the new QR sends nothing again (same pin).
- [x] Each icon/menu state screenshotted: not paired, pairing QR, starting, on, off, problem (port held by `nc -l 8443` started before the app), Terminal set-up (`-VeselDaemonPlist` pointing at an empty scratch file: nothing listens on 8443, no Pair). uv missing is covered by `UVLocatorTests`.
- [x] After a run: `stat -f %Lp` gives 700 on the folder, `certs/` and `venv/`, 600 on `key.pem`, `cert.pem`, `token.sha256`, `vesel.sqlite*`, `server.log`, `server.pid`; `grep` of `server.log` and the app's unified log (`log show --predicate 'process == "Vesel Backup"' --last 1h`) finds no token, no QR text, no health values; `grep -r` for the token under the data folder and `~/Library/Preferences/app.vesel.backup.plist` finds nothing.
- [x] Off → nothing listening on 8443 (`lsof -iTCP:8443 -sTCP:LISTEN`); Quit → no server left (`pgrep -f vesel_server.app`); `kill -9` the app, reopen → exactly one server, orphan replaced.
- [x] Debug run left no login item (`SMAppService` status of the Debug build stays not registered) and no `__pycache__` inside the app bundle.
- **Owner-only:** install Vesel Backup in Applications, open it, Pair phone, scan with the real iPhone on home Wi-Fi; after a sync the menu's last backup updates; log out and in (or restart): it opens by itself and the server is on; turn it off and on from the menu. If macOS asks to allow incoming connections or local network access, allow it. Later, on the Mac mini: the Terminal steps in the README, unchanged.

## Rule gaps
When the code lands:
- `.agents/skills/data/SKILL.md` — "the owner's Mac mini" → "the owner's own Mac". `setup.sh` is the only code that makes the certificate and token; the Mac app runs it and never logs, stores or copies the token or QR; only `token.sha256` is on disk. The app reads the backup file read-only and only for counts.
- `.agents/skills/layers/SKILL.md` — `mac/`: `VeselBackupKit` holds the logic (no UI, no `Process`); the app target composes it; the Mac app never imports the iOS packages.
- `AGENTS.md` Factory — the `layers`, `checks`, `codegen`, `run` and `ships` lines above.
