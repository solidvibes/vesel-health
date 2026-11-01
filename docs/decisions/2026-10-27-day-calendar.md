# Pick a day from a calendar under the title, not a week strip

**Date:** 2026-10-27
**Who decided:** mine

## Context

The first version put a week strip with tiny triple rings at the top of Today, Sleep and Stress, and let Today swipe between days. After seeing it drawn, the owner redesigned: Today is about today.

## Decision

No week strip, no small rings in a strip, no swiping on Today. Tapping the title ("Today", "Night", "Stress") opens a month calendar; each day shows that tab's rings (three on Today, two on Night, calm on Stress). On a past day the title becomes the date with "Back to today". The picked day is shared by the three tabs and goes back to today on a new day. Today shows three big rings, then Recovery, Sleep and Calm week charts (filled dot = inside your normal, hollow = below); Stress shows the same Calm chart.

## Why

Today stays calm and about today; the trend shows as charts; any past day is one tap away, and a whole month reads at a glance in the calendar.

## Alternatives

A week strip at the top of each tab with swiping (first version, replaced). Previous/next arrows (as built before).

## What it means

Supersedes the strip in the first version of the plan. The title on those three tabs is a button for VoiceOver but does not look like one.
