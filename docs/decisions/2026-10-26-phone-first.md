# Phone first, Mac mini as backup

**Date:** 2026-10-26
**Who decided:** mine

## Context

Interview, round 2: where the data and the calculations live.

## Decision

The iPhone holds the full history and does the calculations. The Mac mini receives a copy for backup and heavier analysis later.

## Why

The app must work anywhere, even when the Mac mini is off or out of reach.

## Alternatives

Server as the source of truth: the app would break away from home.

## What it means

Every screen and alert reads from the phone's own database. Upload to the Mac mini is a background copy that can lag behind without harm.
