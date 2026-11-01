<!-- solidvibes:generated from sv 0.1.0 (setup/agents/). Made by solidvibes init; changes here are replaced the next time it runs. -->

# Agents in use

How each agent working in this project shows visuals, asks a choice, runs sub-agents and worktrees, and finds skills. Skills say "show a visual" or "start a sub-agent"; this file says how.

| Agent | Visuals | Sub-agents | Worktrees | Skills folder it reads |
|---|---|---|---|---|
| Claude Code | Artifacts | Agent tool, fresh context | `isolation: "worktree"` | plugin `skills/`, `.claude/skills/` (project), `.claude/skills/` (home folder) |

### Claude Code

- **Visuals** — publish an Artifact (a private page on claude.ai) and give the link. Draw every screen and state separately. When the Artifact tool is not available, write a local HTML file and say where it is.
- **Questions** — a choice goes through AskUserQuestion, on the main thread only: at most 4 options, the recommended one first and marked "(Recommended)", each description saying what it means; "Other" is built in. Open questions stay free text. Sub-agents never ask.
- **Sub-agents** — the Agent tool. Each one starts with a fresh context and sees only its prompt, so pass it the contract's commands and the rule file paths.
- **Worktrees** — start a lane's sub-agent with `isolation: "worktree"`. Clean up finished ones with `solidvibes worktrees --clean`.
- **Skills folder** — Solid Vibes skills come from the plugin (`/sv:<name>`). Project rules live in `.agents/skills/`; Claude Code reads them through the `.claude/skills/<name>` links `solidvibes init` makes.
- **Instructions** — Claude Code reads `AGENTS.md` when the project has no `CLAUDE.md`. A project with a `CLAUDE.md` needs the line `@AGENTS.md` in it, which `solidvibes init` adds.
- **Models** — `opus` for planning, plan review, code review and code in a `risk` area; `sonnet` for the rest.
