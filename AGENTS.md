# vesel-health

## Project

Vesel: a personal iPhone health assistant for one person (the owner). It reads a Polar Loop directly over Bluetooth, works in the background, and alerts when something about sleep, recovery or stress is off.

Everything about the project lives in `docs/`. Start at `docs/README.md`. Why it exists and what must never happen: `docs/intent.md`. Decisions: `docs/decisions/`.

## Non-negotiables

- Health data stays on the phone and the owner's own Mac. Never send it to Polar's, Apple's or anyone else's cloud.
- Works in the background. Never needs the Polar app opened first.
- Never nag. Speak up only when something is actually off.
- Every number can be explained: where it came from and how it was computed.
- Never turn health into a score to chase: no streaks, no bests, no month-to-month arrows on worked-out estimates.

## Without the Solid Vibes plugin

If you aren't the owner, or the skills below aren't installed, skip *Who we build for*, *How every request is handled* and *Visuals*. Follow Non-negotiables, Code principles, the Factory `checks`, and `.agents/skills/`.

<!-- solidvibes:begin audience -->
<!-- solidvibes:generated from sv 0.1.0 (setup/templates/AGENTS.md). Made by solidvibes init; changes between these markers are replaced the next time it runs. -->
## Who we build for

The person in this conversation may not be a developer. Talk to them that way.

- Plain language, outcomes only. Ask who uses it, what they see, what they do next, what "done" looks like. Never ask a tech question.
- Tech choices come from `docs/stack.md`. Decide them yourself and explain one in a plain sentence when it matters ("Your data stays on the phone first, so the app works without internet"). A tech choice that touches a contract `risk` area is shown to them first, with a visual and that one sentence.
- Every decision gets a visual.
- Assume no knowledge of git, a terminal or any framework. Spell out each step, or do it yourself after saying what you will do.
- Say what you are about to do before you do it. One round at a time; group related questions.
- A choice comes as options, each saying what it means and what it costs later, recommended first. How this agent asks: `.solidvibes/agents.md`.
- Never estimate how long the AI takes; ask when they want it.
- Approved means go: don't ask before the obvious next step.
- Reports say what changed and how it was checked. Technical detail goes in the pull request for a reviewer.
<!-- solidvibes:end audience -->

<!-- solidvibes:begin routing -->
<!-- solidvibes:generated from sv 0.1.0 (setup/templates/AGENTS.md). Made by solidvibes init; changes between these markers are replaced the next time it runs. -->
## How every request is handled

Every conversation runs this way. No command needed.

1. **Understand.** First read the titles in `docs/decisions/` and `docs/intent.md`. If the request goes against one, say so with its date and reason ("On 3 March you decided X, because Y") and ask whether to change it; a change is a new decision. Then ask about outcomes, in plain language, until the goal is clear. Restate it in one line.
2. **Size it** with a first estimate: trivial, small, large, several streams, or a new project.
3. **Route.** Say in plain words what happens next, and wait for a go-ahead (except for trivial):

| The request | What happens |
|---|---|
| A new project, or `docs/intent.md` is missing or still the unfilled template (only its italic prompts), or the direction changed | `interview` |
| Unclear or open-ended; a product call; one new screen or a feel change on an existing app; website sections or user-facing words | `brainstorm` |
| The look of a whole new app: "how should the app look", "pick colours", a style for the app; or setup just finished on a new project | `design`, then `plan` |
| Clear and small: one obvious approach, a few files | `brief` (as a sub-agent when the agent has them) |
| "Update the docs" | `brief` |
| "Update everything", "upgrade Flutter", "bring the repo up to date": the tools and packages | `update` |
| Clear but large or several steps | `plan`; after approval, `/clear`, then `go` |
| Several ideas at once | one `brief` or `plan` per stream, one batched decision gate, then `go` for all of them |
| "Is it secure?", before a first release, or a change to sign-in, payments or personal data | `review` with the security lens, on the whole project |
| "Are the docs still true?" | `review` with the docs lens |
| A thought for later, not now | write one paragraph to docs/ideas/<slug>.md under a status: idea line, unless it is already parked; no plan |
| "Put it live", "release it", "merge it" | `release`, one go per step |
| "How does X work?" | answer directly from the code (trivial) |
| Trivial: a typo, a one-line fix, a question | just do it |
| "Hello", "good morning", "let's start", the start of a session | `hello` |
| "Bye", "good night", "done for today", "wrap up" | `bye` |

4. **Show visuals** for decisions, flows and screens (see Visuals). Every decision gets one.
5. **Building ends at green pull requests.** Merging, deploying and store releases go through `release`, and only on the owner's go, one step at a time.
6. **Keep the handover current.** After a brief, a plan approval or a green pull request, update `.solidvibes/handover.md`: one line each under Done, Open and Next. Leave its `## Snapshot` section as it is.
7. **Follow the stack packs.** When `docs/stack.md` lists packs under `## Packs`, load the skill of each pack that covers the files you touch and apply its `## Overrides`. Local overrides win; say in one line when you apply one.

Each backticked name is a skill. An agent without a skill loader reads it at `~/.agents/skills/<name>/SKILL.md`, where `solidvibes install` put it.

### Several ideas at once

1. **Split** the request into streams, one per independent outcome. First read the Factory contract (`## Factory` below; spec: `.solidvibes/factory-contract.md`); if it is missing, follow its missing-contract rule before anything else. Read enough of the code, the plans, `docs/` and the contract's `rules` to know what each stream touches. If a stream's goal is fuzzy, ask now: numbered questions, all streams in one message, with your recommendation per question. Otherwise don't ask; go.
2. **Plan or brief, per stream.** A plan when the stream makes decisions worth reading later: a new behavior, a data shape, a product call, several valid directions. A brief for fixes and adjustments that decide nothing for the future; brief streams go through `brief` (as a sub-agent where possible) and skip the planning step.
3. **Plan sub-agents**, one per plan stream, started together. Each runs the `plan` skill's Phases 1–4 and stops. It does not commit. Then start one fresh review sub-agent per plan from this thread (the `plan` skill's Phase 5), and send its findings back to that plan's planner to fix. It reports: the plan paths, a two-line summary each, the hard-to-undo decisions it made, its assumptions, every changed screen and state, the risk areas touched, and blocking questions.
4. **Commit the plans** together on a branch `plan/<date>-<slug>`.
5. **One decision gate.** One message, numbered across every stream and grouped by stream. Only what is the owner's to call: hard-to-undo decisions, assumptions made without direction, conflicts between plans, setup only the owner can do. Per item: the choice in one or two plain lines, a visual (each screen and state drawn separately), and your recommendation.
6. **Record the answers.** The owner answers per item (`ok`, `3: use X`, `drop 5`). Write each answer into the plans' `## Decisions` as **mine**. Ask again only about what is still open. Then `go` takes all the plans.
<!-- solidvibes:end routing -->

<!-- solidvibes:begin visuals -->
<!-- solidvibes:generated from sv 0.1.0 (setup/templates/AGENTS.md). Made by solidvibes init; changes between these markers are replaced the next time it runs. -->
## Visuals

Show visuals for decisions, flows and screens. Every decision gets one.

How depends on the agent: `.solidvibes/agents.md` says what each agent in use shows (a published page, a local HTML file, or a diagram in the chat). If that file is missing, write a local HTML file and say where it is.

Every page follows the same rule:

- **Picture first.** Text comes after, and at most 3 short lines per box.
- **Every term explained.** One plain line for each: what it is, why it's here.
- **Options side by side** in a table: what you get, what it costs later, the recommended one marked.
- **A system picture shows real things** (phone, server, outside services) with data moving along the arrows. In HTML, animate it with CSS only and show one line per part on hover or tap. Without HTML, draw it as Mermaid.
- **The look.** Once `docs/design/` exists, pages use the app's look. Until then, the Solid Vibes look: warmer colour, bolder type, simple icons.
<!-- solidvibes:end visuals -->

## Working style

- Lead with the answer or the change. Skip preamble.
- Be concise. Short, factual, true.
- Fix what was asked, nothing more. No unasked-for improvements.
- Never invent ratings, reviews, testimonials or user counts.

## Code principles

- Simplest approach that works. No speculative abstractions, feature flags or compatibility shims.
- Validate only where data comes in (user input, other services). Trust the code inside.
- No error handling for things that cannot happen.
- Delete unused code; don't comment it out.
- No comments unless the logic isn't self-evident.
- Never log secrets, tokens or personal data. Never put credentials in the code.

## Factory

- **layers** — screen (SwiftUI) → view model → VeselStorage (GRDB) / VeselCore analysis · band: VeselWearable (Polar SDK) → VeselStorage · background: BLE event / BGTask / App Intent → sync → VeselStorage → alerts · server: VeselSync upload → FastAPI route → SQLite · mac: menu (SwiftUI) → `ServerController` → `VeselBackupKit` → bundled `setup.sh` / server process (uvicorn) / backup SQLite (read-only)
- **checks** — fast: `solidvibes lint . && git ls-files -z '*.swift' | xargs -0 xcrun swift-format lint --strict && swift test --package-path ios/Packages/VeselCore && swift test --package-path ios/Packages/VeselStorage && swift test --package-path ios/Packages/VeselSync && swift test --package-path mac/Packages/VeselBackupKit` · full: `solidvibes lint . && git ls-files -z '*.swift' | xargs -0 xcrun swift-format lint --strict && swift test --package-path ios/Packages/VeselCore && swift test --package-path ios/Packages/VeselStorage && swift test --package-path ios/Packages/VeselSync && swift test --package-path mac/Packages/VeselBackupKit && (cd ios && xcodegen generate && xcodebuild test -project Vesel.xcodeproj -scheme Vesel -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0' -collect-test-diagnostics never -quiet) && (cd mac && xcodegen generate && xcodebuild build -project VeselBackup.xcodeproj -scheme VeselBackup -destination 'platform=macOS' -quiet) && (cd server && uv run pytest)` · format with `git ls-files -z '*.swift' | xargs -0 xcrun swift-format format -i --parallel` (config: `.swift-format`) · the app's `xcodebuild test` runs only the tests that need the Simulator (band and app); the packages above run on the Mac · needs `solidvibes`, `xcodegen` and `uv` (Homebrew) and Xcode on PATH (in Claude Code the plugin puts `solidvibes` there) · CI (`.github/workflows/checks.yml`, every pull request once it is out of draft; each job only when its own files change): `solidvibes lint`, the swift-format lint, `swift test` for VeselCore, VeselStorage, VeselSync and VeselBackupKit, the app's `xcodebuild test` on `iPhone 17` (iOS 27 Simulator), the Mac app build, `uv run pytest`; Xcode 27 on GitHub's `xcode-27` image (macOS 27), the server on Linux. It is not a substitute for the local full checks
- **codegen** — `ios/project.yml` → `cd ios && xcodegen generate` · `mac/project.yml` → `cd mac && xcodegen generate`
- **run** — `cd ios && xcodegen generate && xcodebuild -project Vesel.xcodeproj -scheme Vesel -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0' -derivedDataPath build build && xcrun simctl boot 'iPhone 17 Pro Max' ; xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/Vesel.app && xcrun simctl launch booted app.vesel.ios -VeselScenario normal` (add `-VeselTab today|journal|body` to open a tab); screenshot with `xcrun simctl io booted screenshot <path>`. The Simulator runs on the fake band; the real band and iPhone are owner-only · Mac app: `cd mac && xcodegen generate && xcodebuild -project VeselBackup.xcodeproj -scheme VeselBackup -configuration Debug -derivedDataPath build build && "build/Build/Products/Debug/Vesel Backup.app/Contents/MacOS/Vesel Backup" -VeselServerHome <scratch dir> -VeselServerHost localhost` (add `-VeselDaemonPlist <file>` for the Terminal-set-up state); the menu panel can't be screenshotted headless, so render it with `TEST_RUNNER_VESEL_SHOTS=<dir> TEST_RUNNER_VESEL_SHOTS_HOME=<scratch dir> TEST_RUNNER_VESEL_SHOTS_MODE=pair|states xcodebuild test -project VeselBackup.xcodeproj -scheme VeselBackup -destination 'platform=macOS' -derivedDataPath build -only-testing:VeselBackupSnapshots`. Install for the owner (owner-only): `cd mac && xcodegen generate && xcodebuild -project VeselBackup.xcodeproj -scheme VeselBackup -configuration Release -derivedDataPath build build && ditto "build/Build/Products/Release/Vesel Backup.app" "/Applications/Vesel Backup.app" && open "/Applications/Vesel Backup.app"` · A device install (owner or any builder) needs a gitignored `Signing.local.xcconfig` at the repo root with the builder's `DEVELOPMENT_TEAM` and `VESEL_BUNDLE_PREFIX` (see `README.md`); the Simulator and the checks need none
- **plans** — `docs/plans/YYYY-MM-DD-<slug>.md`
- **docs** — behavior: `docs/how-it-works/` · direction: `docs/direction/` · which goes where: `docs/CONVENTIONS.md` · changelog: `CHANGELOG.md` under `## Unreleased`, one plain sentence
- **rules** — always-on: `AGENTS.md` · topic: `.agents/skills/*/SKILL.md`; a skill applies when the change touches what its description names
- **risk** — anything that sends health data off the phone, the phone ↔ Mac connection (certificate, token), database migrations, deleting data from the band or the phone, pairing and factory reset of the band, secrets
- **ships** — iOS (owner's iPhone only), macOS menu bar app with the server (owner's MacBook), server via Terminal set-up (the owner's own Mac at home)
- **sandbox** — none
- **stack** — `docs/stack.md` (blank 0.1.0)
- **harness** — none
