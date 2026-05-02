---
name: setup-project
description: Bootstrap a project for the review-chain workflow — set the orchestrator as default agent, add a "Working With Claude Code" section to CLAUDE.md, install the TODO.md + TODO(slug) tracking convention, and optionally wire an auto-format hook. Take it or leave it; the review-chain agents work without any of this.
---

You are bootstrapping a project for the `review-chain` workflow. The four pieces are independent — apply whichever ones the user wants, skip the rest.

## What this skill does

1. Set `review-chain:orchestrator` as the project's default agent (`.claude/settings.json`).
2. Add or extend a **Working With Claude Code** section in the project's `CLAUDE.md`.
3. Install the **TODO.md + `TODO(slug)`** tracking convention (create `TODO.md` from template, document in `CLAUDE.md`).
4. *(Optional)* Wire a `PostToolUse` auto-format hook in `.claude/settings.json`.

None of these are required by the `review-chain` agents — agents fall back to "follow project conventions" when this scaffolding isn't present.

## Before you start

Read what's already there:
- `CLAUDE.md` — update, don't overwrite.
- `.claude/settings.json` — merge, don't overwrite. Preserve existing keys and hooks.
- `TODO.md` — leave alone if it exists.

Ask the user (briefly, only if you can't infer):
- Which of the four pieces they want.
- For the auto-format hook: the formatter command (`prettier --write`, `cargo fmt --all`, `gofmt -w`, `black`, etc.). Skip the hook if there's no obvious formatter.

Don't run a long questionnaire.

## 1. Default agent

Add `"agent": "review-chain:orchestrator"` to `.claude/settings.json`. The plugin cannot set this — it has to live in the project's own settings file. Merge with existing keys.

## 2. CLAUDE.md — Working With Claude Code section

Add this section (adapt wording, but keep the substance — these are universal):

```markdown
## Working With Claude Code

- Use Sonnet for Explore agents. Haiku is inadequate for exploration and summarization.
- Prefer dedicated tools (`Read`, `Grep`, `Glob`, `Edit`, `Write`) over Bash equivalents — fewer permission prompts and better tool results.
- Working directory persists between Bash calls. Avoid prepending `cd /path/to/project` to every command; stay at the project root or use absolute paths.
```

If `CLAUDE.md` doesn't exist, create one with at minimum: project name, one-line description, the section above, and a TODO System section (see below if you're installing it).

Don't pad `CLAUDE.md` with generic advice — it's always in context, every token counts.

## 3. TODO.md + TODO(slug) convention

Two pieces that stay in sync:
- `TODO.md` at the repo root — master list. Each entry has a slug (e.g. `config-file`), a description, and the context for the deferral.
- `TODO(slug)` comments in code — mark the exact spot where the work happens. Slug matches an entry in `TODO.md`.

Slugs are the join key. Add an entry → add both. Complete a TODO → remove both.

To install:
1. Create `TODO.md` from `references/todo-template.md` if one doesn't exist.
2. Add a TODO System section to `CLAUDE.md` describing the convention. Suggested wording:

   ```markdown
   ## TODO System

   Two pieces that stay in sync:
   - `TODO.md` at the repo root — master list. Each entry has a slug, a description, and the deferral context.
   - `TODO(slug)` comments in code — mark the spot where the work needs to happen.

   Slugs are the join key. Adding a TODO requires both an entry in `TODO.md` and a `TODO(slug)` comment at the relevant location. Don't use TODOs for vague aspirations — every TODO should describe a concrete thing that needs to happen, in a place where "done" is obvious.
   ```

This is the convention the `review-chain` agents target when they take the `TODO(slug)` disposition. Without it, agents fall back to whatever tracking convention the project already uses (issue tracker, comments, etc.).

## 4. (Optional) Auto-format hook

If the user has a formatter command, add a `PostToolUse` hook to `.claude/settings.json`:

```json
{
  "agent": "review-chain:orchestrator",
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": "<formatter-command-here>" }
        ]
      }
    ]
  }
}
```

Replace `<formatter-command-here>` with whatever the user gave you. Merge with existing hooks if present.

## Done

Show the user the diff of what you changed (or created). One short paragraph per file. Don't paste full file contents.
