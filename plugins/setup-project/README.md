# setup-project

Optional bootstrap for the [`review-chain`](../review-chain/) workflow. Run `/setup-project` in a project to wire up four small things — independently — without committing to the rest.

## What it does

1. **Default agent** — Sets `"agent": "review-chain:orchestrator"` in the project's `.claude/settings.json`. The plugin can't set this for you; it has to live in the project's own settings.
2. **`Working With Claude Code` section in `CLAUDE.md`** — Three universal rules: use Sonnet for Explore agents, prefer dedicated tools over Bash, mind cwd persistence. Adds (or extends) the section.
3. **`TODO.md` + `TODO(slug)` convention** — Creates `TODO.md` from a template and documents the tracking convention in `CLAUDE.md`. The `review-chain` agents target this convention when they take a `TODO(slug)` disposition; without it, agents fall back to whatever tracking convention the project already uses.
4. **(Optional) Auto-format hook** — Adds a `PostToolUse` hook to `.claude/settings.json` that runs the project's formatter (`prettier --write`, `cargo fmt --all`, `gofmt -w`, `black`, etc.) after every `Edit` or `Write`. The skill asks you for the formatter command.

Each step is independent. Skip any of them.

## Why the split

`review-chain` is the headline plugin and works without any project-side scaffolding. `setup-project` exists for people who want a sensible default — not because the agents require it.

## Install

```bash
claude plugin install setup-project@rnortman-plugins
```

Then in your project:

```
/setup-project
```

The skill reads what's already there (existing `CLAUDE.md`, `.claude/settings.json`, `TODO.md`), asks a few short questions, and merges its changes in.
