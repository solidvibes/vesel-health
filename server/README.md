# Vesel backup server

Runs on your own Mac at home. Keeps a copy of what the iPhone stores. Listens on port 8443 on whatever network this Mac is on, over HTTPS with its own certificate and a secret key; only a phone with the QR's key and certificate pin can use it. Never forward the port on your router. It only stores; it never tells the app what to do.

Data lives in `~/Library/Application Support/vesel-server/`: the database (`vesel.sqlite`), the certificate (`certs/`), the key's fingerprint (`token.sha256`, never the key itself) and the log (`server.log`). Backing it up means copying that folder.

## Two ways to run it

Pick one per Mac. Both make the same certificate, key and QR (the app runs this folder's `setup.sh`) and use the same data folder, so the phone keeps working after a switch.

| | Vesel Backup app | Terminal set-up |
|---|---|---|
| For | the MacBook, any Mac on macOS 27 or later | the 2014 Mac mini (macOS 12), headless |
| Runs the server | while you're logged in and the app is open; opens at login | at boot, as a launch daemon |
| Pairing | Pair phone in the menu shows the QR | `setup.sh` shows the QR in Terminal |

### The Vesel Backup app

1. **Install uv:** `brew install uv` (needs [Homebrew](https://brew.sh)). The app uses it to give the server its own Python; the first start downloads Python and the server's packages (no health data).
2. **Install the app.** From the repo: `cd mac && xcodegen generate && xcodebuild -project VeselBackup.xcodeproj -scheme VeselBackup -configuration Release -derivedDataPath build build && ditto "build/Build/Products/Release/Vesel Backup.app" "/Applications/Vesel Backup.app" && open "/Applications/Vesel Backup.app"`. A code update means building and installing it again.
3. **Pair.** Click the drive icon in the menu bar, Pair phone, and scan the code from Vesel > Loop & settings > Set up backup. Pair again makes a new key and keeps the certificate, so the phone re-scans but sends nothing again.
4. If macOS asks to allow incoming connections or local network access, allow it.

The menu shows whether the server is on, the last backup and how many rows of each kind are stored. The switch turns the server off; the phone keeps its rows until it's back on.

### Switch a Mac from the Terminal set-up to the app

The app stands aside while the launch daemon is installed. To switch, stop and remove the daemon, then reopen the app:
```
sudo launchctl bootout system/app.vesel.server
sudo rm /Library/LaunchDaemons/app.vesel.server.plist
```
Same data folder; the phone keeps working. To go the other way, quit the app, switch off Open at login, and follow the Mac mini steps below. Step 5 needs `setup.sh --force` there (a certificate already exists), so the phone scans the new QR once.

### Port 8443 is busy

Something else on this Mac listens on 8443, often the Terminal set-up's server or a copy started by hand. Find it with `lsof -iTCP:8443 -sTCP:LISTEN`, stop it, then click Try again (or reopen the app).

## Set up the Mac mini

Open Terminal on the Mac mini and go step by step.

1. **Check macOS.** Apple menu > About This Mac. Any macOS that still runs Homebrew works; uv brings its own Python.
2. **Check iCloud isn't syncing the data folder.** System Settings > your name > iCloud > iCloud Drive: "Desktop & Documents Folders" may be on, but nothing under `~/Library` is synced. Don't move the data folder elsewhere.
3. **Install the tools** (needs [Homebrew](https://brew.sh)):
   ```
   brew install uv qrencode git
   ```
4. **Get the code** into your home folder (not Desktop or Documents: the background service isn't allowed to read those):
   ```
   git clone https://github.com/solidvibes/vesel-health.git ~/vesel
   ```
5. **Make the certificate, key and QR code:**
   ```
   ~/vesel/server/setup.sh
   ```
   It shows a QR code. On the iPhone: Vesel > Loop & settings > Set up backup, and scan it. The QR holds the secret key; don't photograph or share it. It is shown only once; if you lose it, run `setup.sh --force` and scan the new one (the stored backup stays).
6. **Start the server, now and at every boot.** `setup.sh` prints these two commands at the end; paste them (your Mac password is asked):
   ```
   sudo cp ~/Library/Application\ Support/vesel-server/app.vesel.server.plist /Library/LaunchDaemons/
   sudo launchctl bootstrap system /Library/LaunchDaemons/app.vesel.server.plist
   ```
7. **Allow incoming connections.** If the firewall is on (System Settings > Network > Firewall), let the server's Python through:
   ```
   py="$(realpath ~/vesel/server/.venv/bin/python3)"
   sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add "$py" --unblockapp "$py"
   ```
8. **Don't open the router.** Port 8443 must not be forwarded to the internet. Nothing to do unless someone added a forward.

Check it runs: `tail ~/Library/Application\ Support/vesel-server/server.log` shows `Uvicorn running on https://0.0.0.0:8443`.

After `setup.sh --force` or a code update, restart it: `sudo launchctl kickstart -k system/app.vesel.server`.
To stop it for good: `sudo launchctl bootout system/app.vesel.server` and delete the plist from `/Library/LaunchDaemons/`.

## Why a launch daemon

A launch daemon starts at boot, before anyone logs in, so the backup works after a power cut. `UserName` makes it run as you, so it can use your `~/Library/Application Support` folder and your uv install. A launch agent would only start after you log in.

## For the phone half (format v1)

- `GET /v1/status` → `{"schema": 1, "rows": <int>, "last_received_at": <ISO-8601 UTC or null>}`.
- `POST /v1/batches`, body `{"schema": 1, "table": "<name>", "rows": [{"key": "<string>", "data": {…}}]}` → `{"stored": <n>}`. Upsert by `(table, key)`; sending the same batch twice is harmless.
- `table`: `[a-z_][a-z0-9_]{0,63}`. `key`: 1–512 characters. `data`: a JSON object. 1–1000 rows, body ≤ 5 MB.
- Every request: `Authorization: Bearer <token>`.
- Answers: 401 missing or wrong token · 413 over 5 MB or over 1000 rows · 409 `schema` isn't 1 · 422 any other malformed body.

**QR:** `vesel-backup://<LocalHostName>.local:8443?token=<token>&pin=<pin>`

The phone takes only a `.local` host (or `localhost`, for a test on this Mac).

- `token`: 32 random bytes, base64url without padding (43 characters, `A–Z a–z 0–9 - _`). Sent as is in the header. The server stores only the lowercase hex SHA-256 of its ASCII text.
- `pin`: standard base64 (with `+ / =`) of the SHA-256 of the certificate's DER `SubjectPublicKeyInfo`, percent-encoded in the URL (`%2B %2F %3D`). Decode it with `URLComponents.queryItems` (which doesn't turn `+` into a space).
- The same pin, computed on the Mac:
  ```
  openssl x509 -in ~/Library/Application\ Support/vesel-server/certs/cert.pem -pubkey -noout \
    | openssl pkey -pubin -outform DER | openssl dgst -sha256 -binary | base64
  ```
- On iOS, `SecKeyCopyExternalRepresentation` returns the raw 65-byte EC point, not the SPKI. Prepend the P-256 SPKI header `3059301306072a8648ce3d020106082a8648ce3d030107034200` (hex) before hashing.
- The certificate is self-signed, EC P-256, valid 10 years, SAN `DNS:<LocalHostName>.local`. iOS's default trust check would reject it (self-signed, over 825 days); the phone accepts the server on the pin alone.

For a test on this Mac (plan step 5): `VESEL_SERVER_HOME=/some/tmp VESEL_SERVER_HOST=localhost server/setup.sh`.

`setup.sh --qr-text` is what the app runs: it keeps the certificate if there is one, makes a new token and prints only the QR text. Needs only `openssl` and `shasum`.

## Develop

```
cd server
uv run pytest
```

Logs carry method, path, status and row count only: never bodies, tokens or health values. The path is quoted with control characters escaped, so a request can't fake a log line. `tests/test_logging.py` checks it. `tests/test_setup.py` checks `setup.sh --qr-text` against the contract above, with macOS's `/usr/bin/openssl` and the one on PATH.
