# Mac mini server: a small Python service with SQLite

**Date:** 2026-10-26
**Who decided:** agent's

## Context

Round 5: the 2014 Mac mini receives a copy of the data for backup and heavier analysis.

## Decision

A small Python service (FastAPI) storing everything in one SQLite file, run as a background service on the Mac mini.

## Why

Tiny load, nothing to administer, and Python has the best tools for HRV and signal analysis. SQLite means a backup is copying one file.

## Alternatives

Postgres: more to run and maintain for one user. A Swift server: weaker analysis libraries.

## What it means

The phone and the server agree on one upload format, versioned. The server only stores and analyses; it never drives the app.
