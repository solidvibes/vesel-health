<!-- solidvibes:generated from sv 0.1.0 (setup/templates/factory-contract.md). Made by solidvibes init; changes here are replaced the next time it runs. -->

# Factory contract

Every project says how the Solid Vibes skills work in it. It lives in one place: the `## Factory` section of `AGENTS.md` in the repo root. The skills read it and never assume a stack.

The contract is read from `AGENTS.md` only. A `## Factory` in `CLAUDE.md` does not count: the `interview` skill's setup offers to move it, and moves it only after a yes.

## Fields

| Field | What it says |
|---|---|
| **layers** | The call graph to walk end to end when tracing a change, one chain per entry point |
| **checks** | `fast` (before every commit) and `full` (everything, before handoff) commands |
| **codegen** | File patterns → the command that regenerates their output. Generated files are never hand-edited |
| **run** | How to launch the app, drive it and capture evidence (a screenshot or output). Integration, end-to-end and staging commands, if any |
| **plans** | Where plans go, e.g. `docs/plans/YYYY-MM-DD-<slug>.md` |
| **docs** | Behavior docs (how it works today), direction docs (not committed), the rule for which fact goes where, and the changelog (or `none`) |
| **rules** | The files reviewers check against: always-on files (e.g. `AGENTS.md`) and topic files, and how to tell which topic files apply to a change (usually a skill's description) |
| **risk** | Areas where a change needs a human review |
| **ships** | Build targets (e.g. iOS, Android, macOS, web, server). Drives the platform checks in `review`'s security lens |
| **sandbox** | Extra directories the headless runner may use: `read:` (toolchains, SDKs) and `write:` (caches), one per line. `none` if the base grant is enough |
| **stack** | The project's stack file and the profile it came from, e.g. `` `docs/stack.md` (stack-example 1.0.0) ``, or `none` |
| **harness** | The proof harness command and what it covers, e.g. `` `sv-harness` · levels: unit, db, story, screenshots · targets: ios, web ``, or `none` |

Format: one bullet per field, `- **field** — value`. `sandbox` uses sub-bullets `- read: <path>` / `- write: <path>`. The `solidvibes` command parses these, so keep that exact shape. Commands are runnable as written, from the repo root.

Sandbox paths start with `~` or a variable (`$FLUTTER_ROOT`, `${ANDROID_HOME}`), never a fixed home folder, so the contract works on every machine. A path whose variable is unset or whose folder does not exist yet is skipped with a warning.

## How the skills use it

- **Missing contract.** Interactive: say so in plain words ("this project has no setup file yet, so I don't know how it is built or checked") and offer to run the `interview` skill. Never guess and never fall back to another stack. Headless: end with `Status: blocked: no Factory contract`.
- **Missing field.** Same rule, for that field only. A field set to `none` is answered, not missing.
- **Specialist review.** Spawn one fresh sub-agent per topic `rules` file the diff touches, each told to check the diff against that file only. Spawn one more, a general reviewer, for the plan, the always-on `rules` files, tests and over-engineering. All of them get the `review` skill in table-only mode and the diff. Run them in parallel, then merge their tables and drop duplicates. An agent without sub-agents runs them one after another in one session and says plainly that the review was not independent.
- **Risk.** If the work touches a `risk` area, say so in the plan's risks (or the brief's Risk line) and show the user what it changes for them. In a headless run, add a `## Needs human review` section to the PR body naming the area. The agent never approves its own risk-area change.
- **Commits.** Before each commit: run `codegen` if a matching file changed, then `checks.fast`. Pre-commit hooks must pass; never skip them.
- **The seam: proof through the harness.** Declared, never sniffed. When `harness` is not `none` and its command exists, run `<harness command> status --json`: it lists each level and target as available or not. Available levels go through the harness. The rest fall back to `checks` and `run`. A level with neither gets exact steps for a human, listed as owner follow-ups. Harness exit codes: 0 pass, 1 fail, 2 refused by its guard, 3 not available here (an owner follow-up, never a pass). Skills never check whether an add-on is installed; the contract is the only switch.

## Example: a phone app

```markdown
## Factory

- **layers** — screen → state (Cubit) → repository → local database · remote: repository → API service → server function / Postgres
- **checks** — fast: `cd app && flutter analyze` · full: `cd app && flutter analyze && flutter test`
- **codegen** — `@freezed`, `@JsonSerializable`, `@injectable` → `cd app && dart run build_runner build --delete-conflicting-outputs`
- **run** — `cd app && flutter run -d <booted iOS simulator>`; screenshot with `xcrun simctl io booted screenshot <path>`. Never a physical device.
- **plans** — `docs/plans/YYYY-MM-DD-<slug>.md`
- **docs** — behavior: `docs/how-it-works/` · direction: `docs/direction/` · which goes where: `docs/CONVENTIONS.md` · changelog: `CHANGELOG.md` under `## Unreleased`, one plain sentence
- **rules** — always-on: `AGENTS.md` · topic: `.agents/skills/*/SKILL.md`; a skill applies when the change touches what its description names
- **risk** — sign-in, payments, database migrations, access rules, deleting people's data
- **ships** — iOS, Android
- **sandbox**
  - read: `$FLUTTER_ROOT`
  - write: `~/.pub-cache`
- **stack** — `docs/stack.md` (stack-example 1.0.0)
- **harness** — `sv-harness` · levels: unit, db, story · targets: ios, android
```

## Example: a web app with a desktop shell

```markdown
## Factory

- **layers** — renderer (React) → preload IPC → main process service → repository → Postgres · API: route → service → repository → Postgres
- **checks** — fast: `pnpm -r typecheck && pnpm -r lint` · full: `pnpm -r typecheck && pnpm -r lint && pnpm -r test`
- **codegen** — `packages/db/schema/*.sql` → `pnpm --filter db generate`
- **run** — `docker compose up -d db && pnpm --filter desktop dev`; end-to-end: `pnpm --filter desktop e2e` (saves screenshots to `test-results/`)
- **plans** — `docs/plans/YYYY-MM-DD-<slug>.md`
- **docs** — behavior: `docs/how-it-works/` · direction: `docs/direction/` · which goes where: `docs/CONVENTIONS.md` · changelog: none
- **rules** — always-on: `AGENTS.md` · topic: `.agents/skills/*/SKILL.md`; a skill applies when the change touches what its description names
- **risk** — sign-in, database migrations, the IPC surface, secrets, CI
- **ships** — Electron (macOS), server
- **sandbox**
  - read: `~/.nvm`
  - write: `~/.cache/ms-playwright`
- **stack** — none
- **harness** — none
```
