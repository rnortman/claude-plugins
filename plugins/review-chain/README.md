# review-chain

An adversarial review-chain workflow for Claude Code. Token-frugal, file-based, one-shot agents — the orchestrator never reads or writes an artifact, only paths, hashes, and outcome tokens flow through it.

## Why this exists

The default Claude Code experience puts everything — code, tests, design, debate — into one long conversation. Context bloats; reviewers and authors share state; "let me also look at" rabbit holes are the norm. This plugin enforces a different shape:

- **Every agent is one-shot.** No resumes. A fresh agent gets the job, replies with paths, exits.
- **Every artifact is a file.** The request, designs, reviewer notes, dispositions, and judge verdicts all live on disk. The orchestrator passes paths around; nothing of substance ever rides in conversation.
- **Reviews are adversarial in both directions.** Reviewers second-guess the author. The responder fact-checks every finding before disposing it. The judge second-guesses both.
- **Severity is judged, not declared.** Reviewers state the *consequence* of each finding. The judge weighs it. No "P1/P2/P3" theatre.

The result is a workflow you can actually follow on a ten-finding review without the conversation collapsing under its own weight.

## What's in the plugin

### Orchestrator (default agent)

- **orchestrator** — Traffic cop. Captures the request verbatim, then drives design → implement → review → ship-gate by spawning one-shot subagents. Never reads or writes artifacts itself; only paths, hashes, and outcome tokens flow through it — and because it has read nothing, it passes no hints to the agents it spawns.

### Authoring subagents (one-shot per spawn)

- **designer** — The entry point. Handed only the user's request, it explores the codebase itself — one narrow explorer at a time, at most three related questions each, strictly serial — and writes the design doc, situating the request in the project's big picture. Also the responder in design review, the author of post-freeze design deltas, and the triage authority for every mid-implementation escalation or clarification (see below). Self-cleans drafts via the `cleanup-editor` skill.
- **explorer** — Answers a few related questions about the code, with citations. Cites source code only, never design docs.
- **implementer** — Writes code per the approved design in incremental slices (incremental is the only mode), runs build/tests, commits each increment, and keeps an append-only implementation log — every mode that commits appends to it, review-response fixes included; also acts as the responder in code review.

### Review specialists

Each has focused rubrics baked into its agent definition — the focus areas sharpen attention, but they are not blinders: a reviewer that trips over a real problem outside its lanes reports it under whichever category fits.

Finding IDs are slugs with a category prefix (`security-toctou-user-record-update`, `reuse-reimplements-retry-helper`). Each finding includes file:line, what's wrong, why, and a **consequence** statement. Reviewers do not assign severity tags — severity is judged downstream from the consequence.

**Pre-implementation:**
- **design-reviewer** — Adversarial fact-check of the design doc against the user's request and the code.

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

- **judge** — Spawned fresh per review phase. Reads all notes files + the responder's dispositions doc(s) + the diff (or the design), assesses severity from the consequence text, applies the TODO-acceptability rubric to every added TODO, scans the respond commits no reviewer saw for unfinished fixes and new breakage, and decides APPROVED / REWORK / ESCALATE. One rework round max per phase, then either APPROVED or ESCALATE.

The responder writes a dispositions doc keyed by finding ID. Per finding: **Fixed**, **TODO(slug)** (defer with a slug; TODO comment per project convention — the disposition must self-score the judge's two-question TODO rubric), or **Won't-Do** (requires written rationale arguing the change would actively harm the artifact).

### Triage

Once implementation has started, no escalation reaches you raw. Every reviewer, responder, judge, or round-close-scanner **ESCALATE** and every implementer **CLARIFICATION-NEEDED** spawns a fresh **designer in triage mode**. It treats the escalating agent as one more unreliable witness — reviewers hallucinate, and the workflow scanner is tuned to find *something* — and decides from first principles whether the problem is real, whether fixing it makes the code better or worse at the big-picture level, and what the right fix is regardless of what was proposed. It always writes a `dispositions-triage-<K>.md`; it writes a design delta only when something actually has to change. Its reply routes the orchestrator: `RESUME` (nothing changes; the workflow continues past the stop and you see the dispositions at the next gate), `DELTA` (the delta runs design review and a user gate, then implementation continues), or `ESCALATE` (a genuine user-judgment call — you see the dispositions and the triggering doc).

### Finisher

- **changelog-author** — Runs once, after you approve the ship squash and before the push gate. Reads the workflow's docs and the squash diff, writes (or edits the implementers' own) changelog entry — highlights for humans, most important first, jargon moderated — and amends it into the squash with a precise, detailed commit message written for the LLMs that will read it later.

### Skills

- **/simplify** — User-facing convenience for ad-hoc review outside the full workflow. Runs the citizen-reviewer (quality + reuse + efficiency) against the current diff and applies the fixes.
- **/cleanup-editor** — Invoked by the designer (and available to any author) to self-clean a draft for clarity, contradictions, and answerable open questions.
- **/configure-models** — Generates (and optionally edits) the local `review-chain-models.conf` consumed by the `model-override` hook, so you can re-pin any agent's model per-project or per-user without editing agent files or publishing. Wraps the deterministic template generator bundled in the skill.

### Hooks

- **intercept-explore** (`PreToolUse`) — The built-in `Explore` agent runs on Haiku, which is too weak for this workflow's exploration; the designer is meant to use the `review-chain:explorer` agent (Opus) but agents reflexively reach for `Explore` anyway. This hook intercepts every `Explore` spawn and, by default, **silently upgrades it to Sonnet**. Every other tool call and every other agent passes through untouched.

  The hook is active in any project while `review-chain` is enabled. Claude Code has no native per-plugin hook toggle, so behavior is controlled by a single environment variable, `REVIEW_CHAIN_EXPLORE_HOOK`:

  | Value | Effect |
  | :--- | :--- |
  | *(unset)* | **Default.** Silently override `Explore`'s model to `sonnet`. |
  | `off` (also `0`, `false`, `disable`, `none`) | Do nothing — the built-in `Explore` runs as-is (Haiku). |
  | `deny` | Block the spawn and tell Claude to use `review-chain:explorer` instead. |
  | *a model* (e.g. `opus`, `haiku`, `claude-opus-5`) | Override `Explore`'s model to that model. |

  Set it in any shell or project where you want different behavior, e.g. `export REVIEW_CHAIN_EXPLORE_HOOK=off`. The hook fails open: if `jq` is missing or the input can't be parsed, it does nothing and the spawn proceeds unmodified.

- **model-override** (`PreToolUse`) — Owns the spawn input for every agent except `Explore`, applying two independent policies: **model override** and **background policy**.

  *Model override* re-pins the model an agent runs on **without editing its agent file or publishing a new plugin version**. Every agent's model is normally pinned in its definition (`implementer` → Sonnet, the deep reviewers → Opus, etc.); this hook lets you override those pins per-project or per-shell. It resolves a model by precedence (first hit wins):

  | Priority | Source | Example |
  | :--- | :--- | :--- |
  | 1 | env `REVIEW_CHAIN_MODEL_<AGENT>` | `REVIEW_CHAIN_MODEL_IMPLEMENTER=opus` |
  | 2 | env `REVIEW_CHAIN_MODEL_ALL` | `REVIEW_CHAIN_MODEL_ALL=haiku` |
  | 3 | an explicit model the orchestrator already chose for the spawn | *(respected; config below defers to it)* |
  | 4 | `./.claude/review-chain-models.conf` (project) | `implementer = opus` |
  | 5 | `~/.claude/review-chain-models.conf` (user) | `* = opus` |

  `<AGENT>` is the agent name upper/snake-cased — `comment-rewriter` → `REVIEW_CHAIN_MODEL_COMMENT_REWRITER`. Env vars beat everything (they are the operator's deliberate override); the config file only fills in where the orchestrator didn't already make an explicit choice. With nothing set, the agent's own frontmatter pin governs.

  To set up the config file, run **`/configure-models`** (see Skills below). It reads every agent's current pin and writes a fully-commented template — all lines commented out, so it overrides nothing until you edit it — and can also activate specific overrides for you (e.g. "set implementer to opus"). Use `/configure-models --project` or `--user` to choose the destination.

  Config format is one `agent = model` per line (`#` comments and blank lines ignored; `* = model` applies to every agent; a value of `inherit`/`default`/`-`/empty means "no override"). The built-in `Explore` agent is handled by `intercept-explore` above, not this hook. Fails open like the other hook.

  *Background policy* forces `run_in_background` on spawns whose `subagent_type` starts with `review-chain:`, so the parent is notified on completion instead of blocking. Built-in and third-party agents keep the harness defaults. Controlled by `REVIEW_CHAIN_BACKGROUND_HOOK`:

  | Value | Effect |
  | :--- | :--- |
  | *(unset)* | **Default.** Force `run_in_background: true`. |
  | `off` (also `0`, `false`, `disable`, `none`) | Leave `run_in_background` alone. |
  | `sync` | Force `run_in_background: false` — every review-chain spawn blocks. |

  Recent Claude Code builds already background subagents by default, so what this buys you is *pinning* the behavior: an agent that explicitly passes `run_in_background: false` gets overridden. Setting `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS` wins over this hook — that flag removes `run_in_background` from the `Agent` schema entirely, so the policy is skipped.

  **Why both policies share one hook.** A `PreToolUse` hook's `updatedInput` replaces the *whole* tool input, and when several hooks answer for the same call the last one wins — Claude Code hands every hook the original input and never chains them. Two hooks each returning `updatedInput` for one spawn would silently clobber each other. So the hooks are split by *agent type*, not by concern: `intercept-explore` owns `Explore`, `model-override` owns everything else, and any new spawn-rewriting policy goes inside one of them rather than into a third hook.

## Workflow shape

```
request (verbatim to user-request.md)
       → design (designer explores, serially) → design-review → eli5 → [user gate]
       → implement (incremental rounds of ≤5 increments)
           → per-round review, over that round's commits only:
               pre-pass (prepass-reviewer: slop + scope) → respond → judge
               → deep wave 1 (citizen) → respond/fix
               → deep wave 2 (tracer + test, cumulative diff incl. wave-1 fixes) → respond/fix
               → judge (both waves' dispositions + scan of unreviewed respond commits)
               → workflow-scanner gate: CONTINUE or ESCALATE
           → intermediate round (hit 5, still going): silent squash, NO user gate → the squash is the next round's base → repeat
           → final round (implementer replied "done"): → ship-gate → squash to the original base → changelog-author amends → [push gate]

       any post-freeze ESCALATE / CLARIFICATION-NEEDED → designer triage → RESUME | DELTA (delta review + user gate) | ESCALATE (to you)
```

Each review chain ends at the judge; REWORK = one rework round (fresh responder + fresh judge), then APPROVED or ESCALATE. Design review runs with a single reviewer; the same reviewer → responder → judge shape applies.

The deep pass runs sequential waves rather than one parallel fan: structural findings (citizen) get fixed before the adversarial bug-hunt (tracer) reads the code, so the deepest review happens on near-final code, duplicate findings across reviewers mostly disappear, and each wave's fixes are reviewed by the next wave — with the judge scanning whatever the last respond left unreviewed.

Implementation is incremental only. Increments run in rounds; every round is reviewed by the full pre-pass + deep chain over just that round's commits. Intermediate rounds that pass are squashed automatically (no gate) so the next round starts from a clean base; only the final round — the one where the implementer declared the whole design `done` — surfaces to you at the ship-gate.

## Using it (as a user)

You drive by responding at gates. Between gates, subagents run and write artifacts; you get ≤2-line summaries with paths.

**Gates needing your explicit word** (none implicit — judge APPROVED ≠ user approval):

- **Design** (after agent design-review) — approve or revise.
- **Delta** (any post-freeze design change, whether from triage or from you) — approve or revise, mid-implementation.
- **Ship-gate** (final round only) — squash, then push. Each is a separate authorization (push requires the repo + branch named). Intermediate implementation rounds squash automatically between reviews with no gate; only the final round (the implementer declared the design `done`) stops here for you. Between the two, the changelog author amends the squash.

**Providing feedback at a gate**, in order of preference:

- **Separate notes doc** — Best for substantive comments; tell the orchestrator the path.
- **Edit the artifact in place** — for answering open questions; the orchestrator hands your edited file to a fresh author.
- **Brief chat directives** — one or two specific instructions; the orchestrator writes them verbatim to a notes file (numbered if multiple) for the record.

At the design gate — before implementation starts, while the doc is still a draft — agent re-review of the author's response to your notes is **opt-in**: your notes go straight to a fresh author + fresh judge, and you gate again. Ask if you want a fresh agent reviewer too; your notes travel with it so it cannot override you.

Everywhere else, asking for changes continues the workflow: a design change becomes a delta that runs the full design chain and its own user gate, and a code change becomes a normal implementation increment reviewed by the normal round. You directed the change; you haven't yet seen how an agent rendered it, which is what the reviews and the gate are for.

The orchestrator never resolves an escalation itself: pre-freeze it surfaces at the gate, post-freeze it goes to designer triage, and anything the designer can't settle comes to you.

## Principles

- **One source of truth per concern.** Each specialist's rubric lives in its agent definition. Orchestrator prompts are terse; they never restate the rubric.
- **Orchestrator context stays clean.** No reads or writes of artifacts by the orchestrator.
- **Adversarial but grounded.** Every claim must be backed by source.
- **No persistent / resumed agents.** All agents are one-shot per spawn.
- **The orchestrator never arbitrates.** Post-freeze standoffs go to a fresh designer in triage; what it can't settle goes to the user. No fiat resolution by the orchestrator.

## Pairs well with

[`setup-project`](../setup-project/) — sets the orchestrator as the default agent, adds a `Working With Claude Code` section to `CLAUDE.md`, and installs the `TODO.md` + `TODO(slug)` convention. Optional; `review-chain` works without it.
