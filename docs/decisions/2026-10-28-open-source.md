# Publish the source as vesel-health, source-available

**Date:** 2026-10-28
**Who decided:** mine
**Superseded in part by:** `2026-10-31-apache-licence.md` (the licence)

## Context

The owner wants to show the app ("I built this") and point people who want to learn more to Solid Vibes. This repo has history, the owner's Apple team id, a hostname, scratch paths, a private repo link and notes that are not for the public.

## Decision

- A new repo, `vesel-health`: a cleaned copy of this one in one fresh commit, no history. The app keeps the name Vesel.
- Source-available, not open source: PolyForm Noncommercial 1.0.0, with "Required Notice: Copyright 2026 Stojanov Ventures UG (haftungsbeschränkt)". Anyone may read, build and use it for non-commercial purposes. Commercial licences are available from the UG on request (hello@stojanovventures.com). Superseded by `2026-10-31-apache-licence.md`: Vesel is now open source under Apache 2.0.
- Outside contributions need a signed CLA that transfers all rights to the UG; where German law forbids a transfer, an exclusive, irrevocable, worldwide, unlimited licence including relicensing and commercial use. Lawyer review before the first outside contribution. No business model now; `intent.md` is unchanged on that.
- No Polar name or logo in the name, icon, tagline, screenshots or marketing (Polar SDK licence §4.4). The README says once, factually, that it is built on Polar's BLE SDK under its own licence, and that it is not affiliated with or endorsed by Polar Electro. Polar's notice is kept (§4.3). The SDK is fetched by Swift Package Manager, never copied in.
- In both repos: the Bluetooth prompt says "your band", the camera and local-network prompts say "your Mac", and `intent.md` says the Polar app has an old interface and getting anything done takes many taps.
- No remote and no push yet. Putting it on GitHub (`solidvibes/vesel-health`), and the CLA bot, are a later release step on the owner's go.

## Why

A clean copy is the only way to be sure nothing private ships: history can't be scrubbed reliably. A non-commercial licence lets people learn from it and run their own copy while the UG keeps commercial use; the CLA keeps the UG free to license it any way later.

## Alternatives

MIT (the earlier idea) or AGPL-3.0 (chosen first, then replaced): both allow commercial use by others. Publishing this repo with history: too much private context. "Vessel Health" as the name: the app is Vesel.

## What it means

"Built for one person" (2026-10-26) still holds. Publishing code adds no users: no accounts, no shared server, no App Store. Each builder runs their own copy, with their own band, iPhone, Mac and Apple team, and their health data stays on their own devices.
