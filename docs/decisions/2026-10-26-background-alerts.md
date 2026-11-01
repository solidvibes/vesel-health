# Works in the background and alerts when something is off

**Date:** 2026-10-26
**Who decided:** mine

## Context

Interview, round 2: the app should be a health assistant that works without being opened.

## Decision

The app syncs with the band on its own and compares new readings to the owner's normal range. When something is clearly off (HRV well below baseline, resting HR up, long periods of high stress) it sends a local notification.

## Why

The Polar app only works when opened and nags. The value here is being told, not having to look.

## Alternatives

Show data only when the app is opened. That is the problem being solved.

## What it means

Background Bluetooth, background tasks and local notifications are core, not extras. Alerts are computed on the phone, so they work without the Mac mini. Alert thresholds must be quiet by default: no nagging.
