# Stand-up reminders, off unless turned on

**Date:** 2026-10-29
**Who decided:** mine (the owner)
**Plan:** docs/plans/2026-10-29-sync-stays-fresh.md (phase 3)

## Context

While planning fresher syncs we found the Loop tells the phone when its wearer has been still too long (its own inactivity alert). The owner asked for that to reach the iPhone.

## Decision

A "Stand-up reminders" switch in Loop & settings → Alerts, off by default. When on, the Loop's inactivity alert becomes a quiet local notification on the iPhone. When off, the notice is ignored (it still wakes a read).

## Why

The owner asked for it. It is an opt-in exception to "Never nag" (`docs/intent.md`): it nags only someone who turned it on, and it only passes on what the band itself decided.

## Alternatives

- Leave it out: keeps "Never nag" strict, but the owner wants the reminder on the phone.
- Vesel decides inactivity itself from steps: more rules to tune and explain; the band already does it.

## What it means

Vesel doesn't set the Loop's own inactivity alert: the Polar SDK has no way to read or change it. It must be on in the band's settings; only Polar Flow can switch it on, and opening Polar Flow sends the Loop's data to Polar's cloud, so doing that is the owner's knowing choice. If it is off, no reminder ever comes. No sound, nothing between 22:00 and 07:00, one reminder on screen at a time, not stored and not logged. To reverse: remove the switch; nothing is stored to clean up.
