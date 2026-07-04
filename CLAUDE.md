# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Claude Code plugin marketplace. Two plugins:

- **`review-chain`** — orchestrator + specialist reviewer agents + judge + designer + eli5-explainer + implementer + explorer + requirements-refiner; plus the `simplify`, `cleanup-editor`, `check-todos`, `configure-models`, and `orchestrator` skills; plus two `PreToolUse` hooks (`hooks/`): `intercept-explore` upgrades built-in `Explore` agent spawns off Haiku (default: Sonnet), controlled by the `REVIEW_CHAIN_EXPLORE_HOOK` env var; `model-override` re-pins any agent's model from env vars or a local config file (`.claude/review-chain-models.conf`) without editing agent files or publishing a new version. The `configure-models` skill dumps a commented config template seeded with current defaults (its `references/gen-model-config.sh` is the engine).
- **`setup-project`** — optional bootstrap that wires the orchestrator as the default agent, adds a generic Working-With-Claude-Code section to `CLAUDE.md`, and installs a TODO.md + `TODO(slug)` tracking convention.

The repo has no build system, tests, or application code of its own — its contents get installed into other projects.

## Repository structure

```
.claude-plugin/marketplace.json     # Marketplace registry
plugins/
  review-chain/
    .claude-plugin/plugin.json      # Plugin metadata (name, version, license)
    agents/                         # Agent definitions (YAML frontmatter + Markdown)
    skills/                         # Skill definitions (YAML frontmatter + Markdown)
      <skill>/SKILL.md              # Skill entry point
      <skill>/references/           # Supporting templates/docs
    hooks/
      hooks.json                    # PreToolUse hook registration (both hooks)
      intercept-explore.sh          # Upgrades built-in Explore spawns off Haiku
      model-override.sh             # Re-pins agent models from env/local config
    settings.json                   # Per-project settings template
  setup-project/
    .claude-plugin/plugin.json
    skills/setup-project/
      SKILL.md
      references/todo-template.md
```

## Versioning

Each plugin's `.claude-plugin/plugin.json` and the corresponding entry in `.claude-plugin/marketplace.json` declare a `version` field. Clients use this to decide when to update. **Bump both** (the plugin's `plugin.json` and the marketplace entry) when publishing changes to a plugin.

## Agent definition format

```yaml
---
name: agent-name
description: One-line description
model: inherit
---

[Markdown system prompt for the agent]
```

Agents are spawned fresh per invocation — all agents are one-shots. There are no persistent or resumed agents. Review-time iteration happens by spawning fresh reviewers → a fresh responder → a fresh judge; if REWORK, a fresh responder + fresh judge for one more round.

Always specify `model` explicitly — use `model: inherit` to follow the parent caller's model, or a specific model name (e.g., `model: sonnet`) to pin. Do not omit `model` — the documented default has been inconsistent across Claude Code versions. Do not set `tools` unless you need to *restrict* an agent — omitting it gives the agent all tools available to the parent conversation.

## Skill definition format

```yaml
---
name: skill-name
description: One-line description
---

[Markdown instructions executed when the user invokes /skill-name]
```

Skills can reference files from their `references/` subdirectory and launch agents via the `Agent` tool.

## Architecture: orchestrator, one-shot authors, and review chains

The orchestrator is the default agent for consuming projects (when `setup-project` is installed). It drives an explore → refine → design → implement → review cycle, but is strictly a traffic cop — it spawns subagents for all artifact reads and writes, and consumes only short summaries.

**Authoring subagents (one-shot per spawn — no resumes):**
- **explorer** — surveys the codebase for context relevant to the request, covering all plausible interpretations. Pinned to Sonnet. Cites source code only, never design docs. Context only — never diagnoses, troubleshoots, or root-causes; asked to do so, it declines before reading code. For troubleshooting/root-cause questions the orchestrator runs a context-only exploration, reads the full exploration report into its own context, and then does the diagnostic reasoning itself rather than delegating it.
- **requirements-refiner** — enriches the user's brief request with codebase context from the exploration, resolves ambiguities, and flags tensions between the request and the codebase. Output is "a better prompt" in ELI5-style prose, not a formal spec. No design decisions. Pinned to Opus 4.6. Also acts as the responder in requirements review. Post-freeze requirements changes go in `requirements-delta-<N>.md` docs (delta mode), never edits to the frozen request.
- **designer** — writes the initial design doc; also acts as the responder in design review. Self-cleans the draft via the `cleanup-editor` skill. Post-freeze design changes go in `design-delta-<N>.md` docs (delta mode), never edits to the frozen design.
- **eli5-explainer** — after design review approves, renders the design as a no-context-assumed ELI5 narrative (`design-eli5.md`) presented alongside the design at the user gate. Pinned to Opus 4.6. Explains, never deviates from, the design. Not part of any review chain; regenerated whenever the design changes.
- **implementer** — writes code per the approved design in small increments (incremental is the only mode — there is no single-shot mode), runs build/tests, commits each increment, and records what shipped in an append-only `implementation-log.md`; also acts as the responder in review phases. Pinned to Sonnet via its agent file. The orchestrator does not pass `model` on implementer spawns; sole exception is when the user explicitly requests Opus, in which case the orchestrator passes `model: "opus"` on every implementer spawn for that task.

**Review specialists** (one-shot per phase; each with a focused rubric baked in; reviewers do not assign severity — they state the consequence):
- **requirements-reviewer** — pre-design adversarial review of the refined request against the original request and exploration. Pinned to Opus.
- **design-reviewer** — pre-implementation adversarial review of the design doc against the refined request.
- **slop-reviewer** — thin, diff-only: LLM writing tells, obvious unhandled cases, workarounds for existing bugs visible on the face of the diff.
- **scope-reviewer** — thin, diff + design doc (+ deltas) + implementation log: did this round deliver its log-claimed slice (and, on the final `done` round, is the whole design accounted for), does every log claim trace to the effective design or a delta (else it's undesigned drift), are punts explicit and justified. Round-aware — the orchestrator tells it whether the round is intermediate or final.
- **error-handling-reviewer** — deep: exhaustive handling, reporting-and-response for unexpected situations.
- **correctness-reviewer** — deep: logic bugs, off-by-ones, races, leaks.
- **security-reviewer** — deep: trust boundaries, injection, secrets, auth/authz.
- **test-reviewer** — deep: presence and quality of tests.
- **reuse-reviewer** — deep: duplication with existing code.
- **quality-reviewer** — deep: hacky patterns, unnecessary complexity, observability gaps, workarounds for existing bugs needing context to see.
- **efficiency-reviewer** — deep: performance, missed concurrency, wasteful patterns.
- **code-reviewer** — opt-in generalist, not part of the standard workflow.

**Adjudicator:**
- **judge** — fresh per review phase. Reads all notes files + the responder's dispositions doc + the diff (or the design / refined request), assesses severity from the consequence text, and decides APPROVED / REWORK / ESCALATE. One rework round max per phase, then either APPROVED or ESCALATE.

**Disposition vocabulary** (responder writes per finding ID): **Fixed**, **TODO(slug)** (defer with a slug; TODO comment per project convention), or **Won't-Do** (requires written rationale arguing the change would actively harm the codebase).

**Flow:** orchestrator spawns explorer → requirements-refiner → requirements-reviewer → designer in sequence (one-shots; user gates after requirements and after design). For each review phase (requirements-review, design-review, pre-pass, deep), the orchestrator spawns all relevant reviewers in parallel (one-shots; requirements-review and design-review each have a single reviewer), collects all notes paths, spawns the responder (refiner, designer, or implementer) with all notes paths, then spawns the judge. If the judge returns REWORK, a fresh responder and fresh judge handle one rework round; then either APPROVED or ESCALATE. After design review approves, a fresh `eli5-explainer` renders the design as an ELI5 doc, presented alongside the design at the user gate (and regenerated on any later design revision).

Implementation then runs as **incremental rounds** (the single-shot mode has been removed). Each round is up to 5 one-increment `implementer` spawns; a review round fires when the implementer replies `done` **or** the round reaches its 5th increment. A review round is pre-pass (slop + scope) then deep pass (seven specialists), reviewing only that round's commits (`round base..HEAD`). When an **intermediate** round (5-cap, implementer still `in progress`) clears the final judge, the orchestrator squashes that round's commits into one commit with **no user gate** — that squash becomes the next round's review base, which is why each round's reviews see only its own commits. Rounds repeat, reviewing and squashing, until the implementer replies `done`; only that **final** round reaches the human ship-gate, where the whole task is squashed back to the original base after the user approves. Escalations surface through the judge's escalation doc.

**Spec freeze.** Before the first implementer spawn the orchestrator freezes the spec — `exploration.md`, `requirements.md`, `design.md`, and `design-eli5.md` are committed (or, in scratch/no-VCS working dirs, checksummed) and become immutable; the orchestrator re-verifies they are byte-unchanged after every implementer commit and after each intermediate-round squash, and halts if a frozen doc was edited. Post-freeze, those docs are never revised in place: a design or requirements change is captured in a new `design-delta-<N>.md` / `requirements-delta-<N>.md` doc — written by the designer/refiner in a **delta** mode — that references the original and records only the delta (what it adds/removes/supersedes). The effective spec is the original plus its deltas applied in order; downstream agents (implementer, reviewers, judge) receive every delta path alongside the original.

The `/simplify` skill is a user-facing convenience for ad-hoc review outside the full workflow — it runs quality, reuse, and efficiency reviewers in parallel. The `/cleanup-editor` skill is invoked by the designer (and is available to any author) to self-clean a draft. The `/configure-models` skill generates and edits the local model-override config consumed by the `model-override` hook.

## Conventions

- Commit messages: imperative mood ("Add X", "Fix Y").
- Default branch: `main`.
- All agents read the consuming project's `CLAUDE.md` as their source of truth for project-specific architecture and principles.
- The `TODO(slug)` disposition is workflow vocabulary — the agents always speak it. Whether the actual tracking lives in `TODO.md`, an issue tracker, or somewhere else is a project convention. The `setup-project` plugin installs the `TODO.md` + `TODO(slug)`-comment pattern as one default; without it, agents follow whatever the project already does.
