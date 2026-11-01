# Stack

The tech choices for this project, each with why. The AI decides tech questions from this file, so you never have to. Changing a choice is a decision: it gets a file in `decisions/`.

Started from the blank 0.1.0 profile. `## Checks at hello` lists what the AI checks at the start of each session.

| Area | Choice | Why |
|---|---|---|
| Platforms | iPhone only. Native Swift + SwiftUI, iOS 26 minimum, with WidgetKit widgets | Polar's SDK is native, background Bluetooth and Liquid Glass are Apple-native, and only one phone matters |
| Wearable | Polar Loop over Bluetooth via Polar BLE SDK (Swift Package), behind a `WearableSource` protocol | Reads sleep, Nightly Recharge, 24/7 HR, PPI, skin temp and activity straight off the band; the protocol lets an Apple Watch or another band plug in later |
| Where data lives | SQLite on the phone via GRDB, in a shared App Group folder | The phone is the source of truth; GRDB handles large time series and the widgets can read the same file |
| Analysis | Pure Swift module on the phone (baselines, HRV, stress, alerts), tested on recorded data | Works without the server; every number explainable |
| Background | CoreBluetooth background mode with state restoration, BGTaskScheduler, App Intents for Shortcuts automations, local notifications | The app has to work without being opened |
| Server | Python + FastAPI + SQLite on the owner's Mac: run by the Vesel Backup menu bar app on a newer Mac, or a launch daemon on the 2014 Mac mini | Backup and heavier analysis; tiny load; a backup is one file |
| Mac app | Vesel Backup: Swift + SwiftUI `MenuBarExtra`, macOS 27, XcodeGen; carries the server and `setup.sh`, uses Homebrew's uv for its Python | The owner sees the backup, switches it on and off, and pairs the phone without Terminal |
| Phone ↔ server | HTTPS on the home network only, pinned self-signed certificate + token; the phone queues uploads while away | Listens on whatever network the Mac is on, but only the pinned phone with the token can use it; never forwarded to the internet, no third party |
| Sign-in | None | One user, no accounts |
| Payments | None | Personal tool |
| Analytics, crash reporting | None | No data leaves the phone except to the owner's Mac |
| Tests | Swift Testing for the app's modules; pytest for the server | Standard tools, no extra dependencies |

## Code layout

```
ios/                       Xcode project
  Vesel/                   app target: screens only
  VeselWidgets/            widget extension
  Packages/
    VeselCore/             models, analysis (no I/O)
    VeselStorage/          GRDB database, migrations, queries
    VeselWearable/         WearableSource protocol + Polar implementation
    VeselSync/             upload queue to the owner's Mac
mac/                       Vesel Backup menu bar app (XcodeGen)
  VeselBackup/             app target: menu, pairing, server controller
  Packages/VeselBackupKit/ pure logic (paths, QR check, counts, launch arguments)
server/                    Python backup service (run by the Mac app or the Mac mini's launch daemon)
```

Screens talk to storage and analysis, never to Bluetooth directly. Only `VeselWearable` imports the Polar SDK.

## Checks at hello

- `xcodegen` is installed (`brew install xcodegen`) and `cd ios && xcodegen generate` succeeds.
- The fast checks pass: `swift test` for VeselCore and VeselStorage.
- The Simulator `iPhone 17 Pro Max` (iOS 26.5) exists; the full checks run `xcodebuild test` on it.
