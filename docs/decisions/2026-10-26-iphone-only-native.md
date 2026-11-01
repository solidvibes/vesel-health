# iPhone only, native iOS app with widgets

**Date:** 2026-10-26
**Who decided:** mine

## Context

Interview, round 3: devices. The Flutter app is replaced.

## Decision

A native iPhone app (Swift, SwiftUI, iOS 26 for Liquid Glass) with home-screen and lock-screen widgets. The Mac mini at home runs the server. No Android, no web.

## Why

Polar's SDK is native Swift, background Bluetooth is most reliable with Apple's own APIs, Liquid Glass and widgets are native. Only one phone matters.

## Alternatives

Keep Flutter: needs a hand-written bridge to the Polar SDK and gives cross-platform reach nobody needs.

## What it means

The Flutter app in `app/` is retired on the rebuild branch. Going cross-platform later means a rewrite.
