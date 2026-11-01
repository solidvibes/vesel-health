# Decisions

One file per hard-to-undo call, so nobody has to make it twice: `YYYY-MM-DD-<slug>.md`.

You don't write these files. The AI does, whenever you answer a question that shapes the project, or when it makes a call itself from `stack.md`. This page is here so you can read them.

## Answering a question

When the AI stops to ask, it shows the choice, a picture of what each option means, and its recommendation. Reply in a few words: `ok`, `the second one`, or a sentence of your own. Asking a question back is a fine answer too.

## The template

```markdown
# <the choice, as a short phrase>

**Date:** YYYY-MM-DD
**Who decided:** mine (the owner) or agent's (made from `stack.md` or the project's rules)
**Plan:** docs/plans/YYYY-MM-DD-<slug>.md, if it came from one
**Supersedes:** <path to the earlier decision, or omit>

## Context

What was being decided, and why it came up.

## Decision

What was chosen, in one or two sentences.

## Why

The reasons, in plain words.

## Alternatives

What else was on the table, and why not.

## What it means

What this changes in the project, and what would have to change to reverse it.
```

A changed mind is a new file that names the old one under **Supersedes**. The old one stays.
