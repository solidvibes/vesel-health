# A calmer morning: "I'm up" waits for the Loop, one "Evaluating your night" card

**Date:** 2026-10-30
**Who decided:** mine (the owner); the items marked (agent's) were the agent's
**Plan:** docs/plans/2026-10-30-calmer-morning.md
**Supersedes:** in `2026-10-29-morning-today.md`, the "Processing…" wording and card, and "I'm up" needing the Loop in reach; in `docs/how-it-works/alerts.md`, the morning sleep report being off by default and every notification opening Today; for the morning report only, "quiet by default" of `2026-10-26-background-alerts.md`

## Context

On 30 October the Loop ended the night by itself and Today said "Processing last night", as it should. Later "I'm up" came back although last night was already in: a read where the Loop didn't say whether it still recorded sleep counted as "still asleep". Tapping it then finished at once. And "I'm up" failed with "Couldn't reach your Loop" whenever the Loop wasn't near the phone.

## Decision

- "I'm up" works with the Loop out of reach: the tap is kept (also across launches) and sent with the next read that reaches the Loop. If the Loop already ended the night itself, Vesel just reads. A tap the Loop never gets is dropped after 6 hours; a Loop that is near but refuses drops it, and "I'm up" comes back (agent's).
- From the tap (or the Loop ending the night itself) until last night is stored, one "Evaluating your night" card: "Nothing for you to do. We'll let you know when it's ready." While the tap still waits for the Loop: "Nothing for you to do. Your Loop gets the message as soon as it's near your phone." With the morning report switched off: "Nothing for you to do. It shows here when it's ready." (agent's). A thin moving line, no steps. After "Still in bed" while the Loop still records: no card (agent's). Recovery and Sleep, Journal and the Sleep and Recovery pages say "Evaluating…" where they said "Processing…". No "Couldn't reach your Loop" on "I'm up".
- Once last night is stored, the morning is over: no "I'm up", no "Evaluating", whatever the Loop says later. The Loop's "can't say" counts as still asleep only while last night isn't stored (agent's). A read that can't reach the Loop keeps what it last said (agent's).
- The morning sleep report notification is on by default; tapping it opens that night's Sleep page. Other notifications still open Today.
- Sleep on Body and on the Sleep page's W, M and 3M: one blue bar per night (hours asleep, from 0), your normal shaded behind, like Steps.
- After 2 hours with nothing: "Last night isn't in yet. It fills in on the next read." as before (agent's).

## Why

Getting up is one tap, wherever the Loop is. Once the night is in, nothing asks for it again. The report is what the morning is for, so it comes by itself and opens on the night. It is one quiet summary per night, so on by default stays within "never nag".

## Alternatives

- Keep "Couldn't reach your Loop. Try again.": the owner has to come back and tap again.
- Keep the morning report opt-in: the owner wants it without looking for a switch.
- Keep sleep as a line: bars read as "how much" per night, like Steps.

## What it means

The minutes between the tap and the Loop getting it may count as in bed (accepted). A tap the Loop never gets is dropped after 6 hours, so it can't end the next night. The owner's stored value for the morning report is reset once (agent's) so it follows the new default (on); the switch still turns it off.
- 8 Nov: while Polar may still be finishing the night, the card says "Polar is finishing your night" and the time Vesel stops checking, with no moving line, so a missing night never looks like endless loading. The 2-hour wait stays (mine).
