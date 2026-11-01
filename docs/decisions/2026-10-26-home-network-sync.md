# Upload to the Mac mini over the home network only

**Date:** 2026-10-26
**Who decided:** agent's

## Context

Round 5: how the phone reaches the Mac mini without any cloud in between.

## Decision

The phone uploads when it is on the home network, over an encrypted connection to the Mac mini with a pinned certificate and a secret token. Away from home it queues and catches up later.

## Why

Nothing exposed to the internet and no third-party relay. The phone is the main store, so a delay is harmless.

## Alternatives

Opening a port to the internet: exposes the server. A VPN service such as Tailscale: works away from home but adds a third party. Can be revisited.

## What it means

Backups lag while away from home. Reaching the server from outside needs a new decision.
