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
- **requirements-refiner** — Enriches the user's brief request with codebase context from the exploration, resolves ambiguities, and flags tensions between the request and the codebase. Output is "a better prompt" in ELI5-style prose, not a formal spec. Also acts as the responder in requirements review.
- **designer** — Writes the initial design doc; also acts as the responder in design review. Self-cleans drafts via the `cleanup-editor` skill.
- **implementer** — Writes code per the approved design in incremental slices (incremental is the only mode), runs build/tests, commits each increment, and keeps an append-only implementation log; also acts as the responder in code review.

### Review specialists

Each has focused rubrics baked into its agent definition — the focus areas sharpen attention, but they are not blinders: a reviewer that trips over a real problem outside its lanes reports it under whichever category fits.

Finding IDs are slugs with a category prefix (`security-toctou-user-record-update`, `reuse-reimplements-retry-helper`). Each finding includes file:line, what's wrong, why, and a **consequence** statement. Reviewers do not assign severity tags — severity is judged downstream from the consequence.

**Pre-design:**
- **requirements-reviewer** — Adversarial fact-check of the refined request against the original request and exploration.

**Pre-implementation:**
- **design-reviewer** — Adversarial fact-check of the design doc against the refined request.

**Post-implementation thin pre-pass:**
- **prepass-reviewer** — Two thin lanes in one pass. Slop (diff only): LLM writing tells, obvious unhandled cases, workarounds visible on the face of the diff. Scope (diff + design + implementation log): did this round deliver what its log entries claim (and, on the final `done` round, is the whole design implemented), does every log claim trace to the design or a delta, are punts explicit and justified? Round-aware; can ESCALATE directly on aggregate missing scope.

**Post-implementation deep pass** (two sequential waves; each may read surrounding code):
- **citizen-reviewer** (wave 1) — Long-term-owner lens: quality (hacky patterns, complexity, observability gaps, workarounds), reuse (duplication with existing code), efficiency (performance, missed concurrency, wasteful patterns).
- **tracer-reviewer** (wave 2) — Adversarial code tracing: correctness (logic bugs, off-by-ones, races, leaks), error handling (exhaustive handling, reporting-and-response), security (trust boundaries, injection, secrets, auth/authz).
- **test-reviewer** (wave 2) — Test presence and quality.

The implementer responds to (and fixes) each wave before the next runs, so wave 2 reviews wave 1's fixes as part of the cumulative diff. Structural findings land first; the deepest bug-hunt runs against near-final code.

**Opt-in (not part of standard workflow):**
- **code-reviewer** — Generalist broad sweep. Spawn when the user wants one pair of eyes looking at everything.

### Adjudicator

- **judge** — Spawned fresh per review phase. Reads all notes files + the responder's dispositions doc(s) + the diff (or the design / refined request), assesses severity from the consequence text, applies the TODO-acceptability rubric to every added TODO, scans the respond commits no reviewer saw for unfinished fixes and new breakage, and decides APPROVED / REWORK / ESCALATE. One rework round max per phase, then either APPROVED or ESCALATE.

The responder writes a dispositions doc keyed by finding ID. Per finding: **Fixed**, **TODO(slug)** (defer with a slug; TODO comment per project convention, or Open-Questions entry in the refined request — the disposition must self-score the judge's two-question TODO rubric), or **Won't-Do** (requires written rationale arguing the change would actively harm the artifact).

### Skills

- **/simplify** — User-facing convenience for ad-hoc review outside the full workflow. Runs the citizen-reviewer (quality + reuse + efficiency) against the current diff and applies the fixes.
- **/cleanup-editor** — Invoked by the designer (and available to any author) to self-clean a draft for clarity, contradictions, and answerable open questions.
- **/configure-models** — Generates (and optionally edits) the local `review-chain-models.conf` consumed by the `model-override` hook, so you can re-pin any agent's model per-project or per-user without editing agent files or publishing. Wraps the deterministic template generator bundled in the skill.

### Hooks

- **intercept-explore** (`PreToolUse`) — The built-in `Explore` agent runs on Haiku, which is too weak for this workflow's exploration; the orchestrator is meant to use the `review-chain:explorer` agent (Opus) but reflexively reaches for `Explore` anyway. This hook intercepts every `Explore` spawn and, by default, **silently upgrades it to Sonnet**. Every other tool call and every other agent passes through untouched.

  The hook is active in any project while `review-chain` is enabled. Claude Code has no native per-plugin hook toggle, so behavior is controlled by a single environment variable, `REVIEW_CHAIN_EXPLORE_HOOK`:

  | Value | Effect |
  | :--- | :--- |
  | *(unset)* | **Default.** Silently override `Explore`'s model to `sonnet`. |
  | `off` (also `0`, `false`, `disable`, `none`) | Do nothing — the built-in `Explore` runs as-is (Haiku). |
  | `deny` | Block the spawn and tell Claude to use `review-chain:explorer` instead. |
  | *a model* (e.g. `opus`, `haiku`, `claude-opus-4-8`) | Override `Explore`'s model to that model. |

  Set it in any shell or project where you want different behavior, e.g. `export REVIEW_CHAIN_EXPLORE_HOOK=off`. The hook fails open: if `jq` is missing or the input can't be parsed, it does nothing and the spawn proceeds unmodified.

- **model-override** (`PreToolUse`) — Re-pins the model an agent runs on **without editing its agent file or publishing a new plugin version**. Every agent's model is normally pinned in its definition (`implementer` → Sonnet, the deep reviewers → Opus, etc.); this hook lets you override those pins per-project or per-shell. It fires on every agent spawn and resolves a model by precedence (first hit wins):

  | Priority | Source | Example |
  | :--- | :--- | :--- |
  | 1 | env `REVIEW_CHAIN_MODEL_<AGENT>` | `REVIEW_CHAIN_MODEL_IMPLEMENTER=opus` |
  | 2 | env `REVIEW_CHAIN_MODEL_ALL` | `REVIEW_CHAIN_MODEL_ALL=haiku` |
  | 3 | an explicit model the orchestrator already chose for the spawn | *(respected; config below defers to it)* |
  | 4 | `./.claude/review-chain-models.conf` (project) | `implementer = opus` |
  | 5 | `~/.claude/review-chain-models.conf` (user) | `* = opus` |

  `<AGENT>` is the agent name upper/snake-cased — `requirements-refiner` → `REVIEW_CHAIN_MODEL_REQUIREMENTS_REFINER`. Env vars beat everything (they are the operator's deliberate override); the config file only fills in where the orchestrator didn't already make an explicit choice. With nothing set, the agent's own frontmatter pin governs.

  To set up the config file, run **`/configure-models`** (see Skills below). It reads every agent's current pin and writes a fully-commented template — all lines commented out, so it overrides nothing until you edit it — and can also activate specific overrides for you (e.g. "set implementer to opus"). Use `/configure-models --project` or `--user` to choose the destination.

  Config format is one `agent = model` per line (`#` comments and blank lines ignored; `* = model` applies to every agent; a value of `inherit`/`default`/`-`/empty means "no override"). The built-in `Explore` agent is handled by `intercept-explore` above, not this hook. Fails open like the other hook.

## Workflow shape

```
explore → requirements → requirements-review → [user gate]
       → design → design-review → [user gate]
       → implement (incremental rounds of ≤5 increments)
           → per-round review, over that round's commits only:
               pre-pass (prepass-reviewer: slop + scope) → respond → judge
               → deep wave 1 (citizen) → respond/fix
               → deep wave 2 (tracer + test, cumulative diff incl. wave-1 fixes) → respond/fix
               → judge (both waves' dispositions + scan of unreviewed respond commits)
           → intermediate round (hit 5, still going): silent squash, NO user gate → the squash is the next round's base → repeat
           → final round (implementer replied "done"): → ship-gate (squash to the original base + push, separate user gates)
```

Each review chain ends at the judge; REWORK = one rework round (fresh responder + fresh judge), then APPROVED or ESCALATE. Escalations surface as a doc the user arbitrates. Requirements-review and design-review each run with a single reviewer; the same reviewer → responder → judge shape applies.

The deep pass runs sequential waves rather than one parallel fan: structural findings (citizen) get fixed before the adversarial bug-hunt (tracer) reads the code, so the deepest review happens on near-final code, duplicate findings across reviewers mostly disappear, and each wave's fixes are reviewed by the next wave — with the judge scanning whatever the last respond left unreviewed.

Implementation is incremental only. Increments run in rounds; every round is reviewed by the full pre-pass + deep chain over just that round's commits. Intermediate rounds that pass are squashed automatically (no gate) so the next round starts from a clean base; only the final round — the one where the implementer declared the whole design `done` — surfaces to you at the ship-gate.

## Using it (as a user)

You drive by responding at gates. Between gates, subagents run and write artifacts; you get ≤2-line summaries with paths.

**Gates needing your explicit word** (none implicit — judge APPROVED ≠ user approval):

- **Requirements** (after refinement and agent review) — approve, supply answers, edit in place, or redirect.
- **Design** (after agent design-review) — approve or revise.
- **Ship-gate** (final round only) — squash, then push. Each is a separate authorization (push requires the repo + branch named). Intermediate implementation rounds squash automatically between reviews with no gate; only the final round (the implementer declared the design `done`) stops here for you.

**Providing feedback at a gate**, in order of preference:

- **Separate notes doc** — Best for substantive comments; tell the orchestrator the path.
- **Edit the artifact in place** — for answering open questions; the orchestrator hands your edited file to a fresh author.
- **Brief chat directives** — one or two specific instructions; the orchestrator writes them verbatim to a notes file (numbered if multiple) for the record.

After your review, agent re-review on revision is **opt-in**. Default is: your notes go straight to a fresh author + fresh judge — no agent reviewers. Ask if you want a fresh agent reviewer; your notes will travel with it so it cannot override you.

Escalations from the judge always surface to you as a doc; the orchestrator never resolves them.

## Principles

- **One source of truth per concern.** Each specialist's rubric lives in its agent definition. Orchestrator prompts are terse; they never restate the rubric.
- **Orchestrator context stays clean.** No reads or writes of artifacts by the orchestrator.
- **Adversarial but grounded.** Every claim must be backed by source.
- **No persistent / resumed agents.** All agents are one-shot per spawn.
- **The user arbitrates ESCALATE.** Judge-to-responder standoffs surface as an escalation doc; the user resolves them. No fiat resolution by the orchestrator.

## Pairs well with

[`setup-project`](../setup-project/) — sets the orchestrator as the default agent, adds a `Working With Claude Code` section to `CLAUDE.md`, and installs the `TODO.md` + `TODO(slug)` convention. Optional; `review-chain` works without it.
