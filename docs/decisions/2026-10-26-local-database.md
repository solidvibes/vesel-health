# The phone stores data in SQLite (GRDB)

**Date:** 2026-10-26
**Who decided:** agent's

## Context

Round 5: where data lives on the phone. 24/7 heart rate and beat-to-beat data mean many thousands of samples a day.

## Decision

One SQLite database through GRDB, stored in a shared App Group folder so the widgets can read it.

## Why

SQLite handles large time series well, GRDB gives reactive queries for SwiftUI, and the widgets need shared access.

## Alternatives

SwiftData: slow with large sample tables and awkward to share with widgets. Plain files: no queries.

## What it means

Schema changes go through GRDB migrations. Changing the database later means migrating stored history.
