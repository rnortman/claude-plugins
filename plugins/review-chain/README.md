# review-chain

An adversarial review-chain workflow for Claude Code. Token-frugal, file-based, one-shot agents — the orchestrator never reads or writes an artifact, only paths and short summaries flow through it.

## Why this exists

The default Claude Code experience puts everything — code, tests, design, debate — into one long conversation. Context bloats; reviewers and authors share state; "let me also look at" rabbit holes are the norm. This plugin enforces a different shape:

- **Every agent is one-shot.** No resumes. A fresh agent gets the job, replies with paths, exits.
- **Every artifact is a file.** Designs, requirements, reviewer notes, dispositions, and judge verdicts all live on disk. The orchestrator passes paths around; nothing of substance ever rides in conversation.
- **Reviews are adversarial in both directions.** Reviewers second-guess the author. The responder fact-checks every finding before disposing it. The judge second-guesses both.
- **Severity is judged, not declared.** Reviewers state the *consequence* of each finding. The judge weighs it. No "P1/P2/P3" theatre.

The result is a workflow you can actually follow on a ten-finding review without the conversation collapsing under its own weight.

## What's in the plugin

### Orchestrator (default agent)

- **orchestrator** — Traffic cop. Drives explore → refine → design → implement → review → ship-gate by spawning one-shot subagents. Never reads or writes artifacts itself; only paths and ≤3-line summaries flow through it.

### Authoring subagents (one-shot per spawn)

- **explorer** — Surveys the codebase for context relevant to the request. Cites source code only, never design docs.
- **requirements-refiner** — Turns the user's request plus the exploration report into a refined spec.
- **designer** — Writes the initial design doc; also acts as the responder in design review. Self-cleans drafts via the `cleanup-editor` skill.
- **implementer** — Writes code per the approved design, runs build/tests, commits; also acts as the responder in code review.

### Review specialists

Each has a focused rubric baked into its agent definition. Orchestrator spawns the relevant specialists in parallel, collects findings paths, then spawns the responder and judge.

Findings are numbered with a per-reviewer prefix (`security-1`, `correctness-3`, etc.). Each finding includes file:line, what's wrong, why, and a **consequence** statement. Reviewers do not assign severity tags — severity is judged downstream from the consequence.

**Pre-implementation:**
- **design-reviewer** — Adversarial fact-check of the design doc against requirements.

**Post-implementation thin pre-pass** (parallel, diff-only):
- **slop-reviewer** — LLM writing tells, obvious unhandled cases, workarounds for existing bugs visible on the face of the diff.
- **scope-reviewer** — Did the implementation finish the job? Are punts explicit and justified?

**Post-implementation deep pass** (parallel, may read surrounding code):
- **error-handling-reviewer** — Exhaustive handling, reporting-and-response for unexpected situations.
- **correctness-reviewer** — Logic bugs, off-by-ones, races, leaks.
- **security-reviewer** — Trust boundaries, injection, secrets, auth/authz.
- **test-reviewer** — Test presence and quality.
- **reuse-reviewer** — Duplication with existing code.
- **quality-reviewer** — Hacky patterns, unnecessary complexity, observability gaps, workarounds for existing bugs that need context to see.
- **efficiency-reviewer** — Performance, missed concurrency, wasteful patterns.

**Opt-in (not part of standard workflow):**
- **code-reviewer** — Generalist broad sweep. Spawn when the user wants one pair of eyes looking at everything.

### Adjudicator

- **judge** — Spawned fresh per review phase. Reads all notes files + the responder's dispositions doc + the diff (or design doc), assesses severity from the consequence text, decides APPROVED / REWORK / ESCALATE. One rework round max per phase, then either APPROVED or ESCALATE.

The responder writes a dispositions doc keyed by finding ID. Per finding: **Fixed**, **TODO(slug)** (defer with a slug; TODO comment per project convention), or **Won't-Do** (requires written rationale arguing the change would actively harm the codebase).

### Skills

- **/simplify** — User-facing convenience for ad-hoc review outside the full workflow. Runs quality, reuse, and efficiency reviewers in parallel against the current diff and applies the fixes.
- **/cleanup-editor** — Invoked by the designer (and available to any author) to self-clean a draft for clarity, contradictions, and answerable open questions.
- **/orchestrator** (skill version of the orchestrator agent) — Lets you trigger the orchestrator's workflow as a skill from any agent.

## Workflow shape

```
explore → requirements → [user gate] → design → design-review → [user gate]
       → implement → pre-pass review (slop + scope) → deep review (7 specialists)
       → ship-gate (squash + push, separate user gates for each)
```

Each review phase: parallel reviewers → responder (with all notes paths) → judge. REWORK = one rework round (fresh responder + fresh judge), then APPROVED or ESCALATE. Escalations surface as a doc the user arbitrates.

## Principles

- **One source of truth per concern.** Each specialist's rubric lives in its agent definition. Orchestrator prompts are terse; they never restate the rubric.
- **Orchestrator context stays clean.** No reads or writes of artifacts by the orchestrator.
- **Adversarial but grounded.** Every claim must be backed by source.
- **No persistent / resumed agents.** All agents are one-shot per spawn.
- **The user arbitrates ESCALATE.** Judge-to-responder standoffs surface as an escalation doc; the user resolves them. No fiat resolution by the orchestrator.

## Pairs well with

[`setup-project`](../setup-project/) — sets the orchestrator as the default agent, adds a `Working With Claude Code` section to `CLAUDE.md`, and installs the `TODO.md` + `TODO(slug)` convention. Optional; `review-chain` works without it.
