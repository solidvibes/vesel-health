<!-- solidvibes:generated from sv 0.1.0 (setup/templates/docs/CONVENTIONS.md). Made by solidvibes init; changes here are replaced the next time it runs. -->

# How these docs work

The `docs/` folder is the source of truth for how this project works. Read it and you should understand the whole thing (what each part does, its limits, why it exists) without opening the code.

## Which fact goes where

| Where | What goes in | Kept current by |
|---|---|---|
| `README.md` | One line on the project, the map, and "Right now": done, next, blocked | `interview` writes it; `go` and `brief` keep "Right now" current |
| `intent.md` | Why it exists, who it is for, what must never happen, what success is, what is out of scope | `interview` writes it; it changes only through a decision |
| `stack.md` | The tech choices, each with why | `interview`; changing a choice is a decision |
| `how-it-works/<part>.md` | How one part behaves today, with a status line | `plan` (Planned), `go` and `brief` (Built, in the same change) |
| `direction/` | The vision and where it is going. Not a commitment | `interview`, `brainstorm` |
| `design/` | The look: `direction.md`, `system.md` (the source of the app's theme), `screens.md` with the system picture | `design`; changing an approved step is a decision |
| `decisions/YYYY-MM-DD-<slug>.md` | One hard-to-undo call each: context, decision, why, alternatives, who decided | `interview`, `brainstorm`, `plan`, `bye` |
| `plans/`, `ideas/` | Plans with a `status:` line at the top; parked ideas | `plan`, `go`; an idea is one paragraph in `ideas/` |
| `../CHANGELOG.md` | One plain sentence per change people notice, under `## Unreleased` | `brief`, `go` |

## Status lines

Every `how-it-works/` doc opens with a status line.

| Line | Means |
|---|---|
| `**Status:** Planned.` | Decided and scoped, not built. The doc describes the intent. |
| `**Status:** Built.` | Live in the code. The doc describes what it does. |
| `**Status:** Open question.` | Not decided. Don't build it either way without asking. |

A doc moves from Planned to Built in the same change that ships the code, never before. A Planned doc is the spec; a Built doc is fact, and gets fixed when the fact changes.

## Docs and rules

Two layers, different jobs.

| | **Docs** (`docs/**/*.md`) | **Rules** (`.agents/skills/*/SKILL.md`) |
|---|---|---|
| Answers | What does this do? | How do I change the code? |
| Holds | Facts (limits, schedules, defaults), intent, product do's and don'ts | Code rules, gotchas, the files and names to touch |
| Example | "Reminders go out at 8 in the morning, in the person's own time zone." | "Schedule reminders through the queue, never from the screen." |
| Reader | Anyone: the owner, a new helper, an AI getting its bearings | An AI about to change that part |

A fact about behavior goes in the docs. A rule about changing the code goes in a rule. A rule that restates a fact the docs own will drift: move the fact here and point at it.

A rule with a docs counterpart opens with a one-line pointer:

```
# <Rule title>

> What it does lives in `docs/how-it-works/<part>.md`.
> This rule covers: <which files and which rules>.
```

## The shape of a how-it-works doc

```
# <Part>

**Status:** <Planned. | Built. | Open question.>

> One line: what we would tell a user this is.

## Intent
Why it exists. What problem it solves.

## How it works
The facts, concrete and easy to scan. Limits, schedules, defaults. Tables and bullets over prose.

## Do / Don't
Product rules. Code rules live in `.agents/skills/`.

## Open questions
Only real ones. Delete the section when there are none.
```

## Keeping it true

- `brief` reconciles the docs with each change; "update the docs" is a brief. `review` with the docs lens lists every claim the code no longer backs.
- A plan's `**Touches**` line names the docs it changes, so a decision stays findable from the doc later.
- This file is made by `solidvibes init` and replaced when it runs again. Project-specific notes go in `README.md`.
