# Changelog

Notable changes to plugins in this marketplace. Versions are per-plugin and follow [Semantic Versioning](https://semver.org/).

## review-chain

### 0.20.1 — 2026-07-17

- **requirements-refiner, designer: explorer-spawn primer.** When spawning their own explorer, pass it an explicit output path — a fresh file in the working dir (e.g. `exploration-refiner-<N>.md` / `exploration-designer-<N>.md`) — then read that file.

### 0.20.0 — 2026-07-16

Hands off sub-subagents: orchestrators were seeing "subagent waiting on its own subagent" notifications and autonomously nudging the waiting agent to "quit waiting and get to work" — the explorer kept running (and billing) while the expensive designer redid its work.

- **orchestrator: new "Sub-subagents — hands off" rule.** Refiners, designers, reviewers, and judges are authorized to spawn their own subagents and to wait idle on their completion — that's the intended design. Sub-subagent-waiting notifications are informational: ignore them, take no action, never SendMessage a subagent to "stop waiting" or "proceed without the explorer".
- **orchestrator: matching Never bullet** — never nudge, interrupt, or "unblock" a subagent waiting on its own subagent.

### 0.19.0 — 2026-07-16

Implementer subagent ban: implementers were reading the design and code to orient, deciding the scope was too big, and then spawning subagents to do the actual implementation — burning the orientation work and handing the edits to a context-free agent.

- **implementer: new "No subagents (every mode)" rule.** Never spawn subagents — no `Agent`/`Task` calls, no delegating the implementation; every code edit is made by the implementer itself. Scope too big? Cut scope: shrink the increment to a coherent slice at a natural seam and reply `in progress` so the orchestrator spawns the next increment.

### 0.18.0 — 2026-07-16

Green commits always: the implementer's blanket permission to commit intermediate increments with `--no-verify` is gone. Implementers were leaning on it constantly to commit non-green code — and citing their own agent definition as requiring it.

- **implementer: `--no-verify` forbidden.** Every commit must pass pre-commit checks. Sole exception: the design *explicitly* declares an intermediate state that cannot commit green, and the commit is exactly that declared state (design's words cited in the log entry). "My increment isn't finished" doesn't qualify.
- **New "Pre-commit hooks fail" stop procedure (any mode).** Hooks reject a commit outside the design-declared exception and it can't be fixed honestly within scope → the implementer is off-script: no committing, no disabling/skipping/weakening hooks, no hacking code to appease them. It leaves the work uncommitted, writes `hook-failure.md` (what changed, which hooks failed with what output, its read on why), and stops.
- **orchestrator: routes the hook-failure stop** — escalate to the user; never direct any agent to commit with `--no-verify`.

### 0.17.0 — 2026-07-16

Requirements-refiner and designer see the forest: both must ground their work in the project's big picture, and both may spawn their own explorers when the handed exploration falls short.

- **requirements-refiner: "See the forest" mission.** The refiner must gather enough context to understand the project's intent, purpose, and architectural principles — not just the immediate request — and the refined request situates the ask as one tree within that forest, naming highly relevant neighboring trees. Explicitly not a requirements lawyer: no "specification" output, no numbered-requirements paragraphs; requirement identifiers, when needed, are meaningful slugs. Draft mode gains a "The forest" section in the doc structure.
- **designer: "Forest first, then trees."** The designer establishes big-picture project context before prescribing anything, in every mode (draft, revise, respond, delta) — building it itself when the requirements phase was skipped — then focuses on the trees: the placement and shape of each, and which to cut down.
- **Both agents authorized to spawn `review-chain:explorer` subagents** when the exploration they were handed leaves needed questions unanswered, and to read code directly — reserved for the most critical pieces, leaning on explorers otherwise.

### 0.16.0 — 2026-07-13

usage-guard: the watchdog is now tenacious — API outages no longer make it give up. It rides through failures with rate-limited degraded notices, and the session owns the kill switch.

- **No more disarm on read failures.** The old behavior (`WATCHDOG-DISARMED` + exit after 5 consecutive unreadable polls) treated a routine extended API outage as fatal. The watchdog now retries forever (every 120s while failing — polling is cheap; only stdout lines cost LLM tokens).
- **New `WATCHDOG-DEGRADED` / `WATCHDOG-RECOVERED` events.** After 5 consecutive failures the session gets one degraded notice (blind duration, failure count, "do not assume headroom", and an explicit reminder that it can kill the monitor), then at most one re-notice per 30 minutes while the outage continues. When readings resume, one recovery line reports the blind duration and current utilization. Short blips (under 5 failures) stay silent.
- **`WATCHDOG-DISARMED` narrowed** to the startup no-OAuth-credentials case, where retrying can't help. The `WATCHDOG_EXIT_ON_ALERT=1` background fallback also exits on a degraded notice (background shells only surface output on exit).
- **SKILL.md: new "Killing the watchdog" doctrine.** The watchdog never self-terminates, so the session must kill the monitor when the task is done or it's blocked waiting on the user — waking an idle session is a full prompt-cache miss, so an unattended watchdog wastes exactly the tokens it exists to protect. Re-arm when active work resumes.

### 0.15.0 — 2026-07-12

usage-guard: per-percent alarms from 90% up, tiers moved to 90/94/97, and faster polling while alerting — so a session actually watches usage tick toward the wall (two parallel sessions can burn the tail of a window fast).

- **Alarm on every 1% increase from 90%.** The watchdog previously fired only on tier crossings; now once utilization hits 90% it wakes the session on every integer-percent increase. Alarm lines are `USAGE-<pct>` (e.g. `USAGE-92`) with a tier-based instruction body; no duplicate alarms for the same percentage, and the counter resets on `USAGE-RESET`.
- **Tiers moved from 90/95/98 to 90/94/97** (mild / escalation / wind-down), buying more headroom before the wall.
- **Alert-mode poll cap of 120s.** The adaptive cadence could sleep up to 480s at 90%, batching several percent into one jump; while in any alert tier polls now come at most 120s apart so per-percent ticks are actually observed.
- **SKILL.md doctrine rewritten** around the `USAGE-<pct>` format with tier ranges (90–93 / 94–96 / 97+); CLAUDE.md updated to match.

### 0.14.1 — 2026-07-12

usage-guard hardening: the watchdog now rides through the window reset instead of terminating, times the reset message correctly, and the manual check surfaces model-scoped weekly caps.

- **usage-watchdog.sh no longer exits on alert.** After `USAGE-98` it keeps running, waits out the window, and — once the 5-hour window actually rolls over — wakes the session with `USAGE-RESET`, then stays running to guard the new window (silent again until 90%). The scheduled cron wakeup is now backup insurance, not the primary mechanism.
- **Reset message is time-gated (fixes early/false resets).** The API can report the utilization drop a few seconds *before* the real reset; firing then just woke the session back into the still-throttled old window. `USAGE-RESET` now fires only once we're ≥45s past the guarded window's nominal reset time **and** the API confirms the roll (utilization dropped, or `resets_at` jumped forward a fresh window). The guarded boundary is held fixed for the whole alert so a poll landing in the post-roll cushion can't overwrite it with the next window's reset time (which had made `USAGE-RESET` unreachable and frozen the next window's tier alarms).
- **Uniform sleep pacing across tiers.** While in any alert tier, each sleep is capped so it never overshoots the nominal reset + 45s (floored at 30s) — so tier crossings (95→98) are never slept through while still landing a wake right after the real reset.
- **Portability + robustness.** `to_epoch` now parses the real timestamp shapes on BSD/macOS (`Z` suffix, fractional seconds, `+HH:MM` offsets), so the time-gate isn't silently dead there; a non-numeric `utilization` now routes to the loud `WATCHDOG-DISARMED` path instead of crashing the loop under `set -u`.
- **usage-check.sh reports model-scoped weekly caps.** The top-level `seven_day_*` fields are `null` now; scoped limits (e.g. a Fable-specific weekly cap) live in `.limits[]` with a non-null `.scope`. The check now prints each one generically, so any future scoped limit surfaces too.

### 0.14.0 — 2026-07-12

New `/usage-guard` skill: an opt-in, user-invoked-only watchdog on the account's 5-hour usage window, so a long-running session schedules its own post-reset wakeup instead of hitting the limit mid-task.

- **usage-guard skill** (`disable-model-invocation: true` — the user decides when a session is long-running enough to need it; it stays out of the orchestrator prompt entirely). Arms `references/usage-watchdog.sh` under the Monitor tool (`persistent: true`); each alarm line wakes the session — even fully idle — as its own notification. Carries the response doctrine per tier plus a `run_in_background` + `WATCHDOG_EXIT_ON_ALERT=1` re-arm fallback for Monitor-less sessions.
- **usage-watchdog.sh**: polls `GET /api/oauth/usage` (undocumented endpoint backing the CLI's `/usage` view; response shape verified 2026-07-12) with the OAuth token from `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json`, re-read every poll so profile-switched sessions hit the right account and CLI token refreshes are picked up. Adaptive cadence: `(99 − utilization)` minutes clamped to [60s, 480s] — the 60s floor is only reached at 99%. Escalating tiers: `USAGE-90` (schedule the post-reset cron wakeup now as insurance; prefer serial subagents), `USAGE-95` (wakeup must be set; only small strictly-bounded subagent work), `USAGE-98` (go to sleep now — terminal, exits). Also emits `USAGE-RESET` if the window rolls over while armed, and disarms loudly (`WATCHDOG-DISARMED`) rather than silently on missing credentials or 5 consecutive read failures.
- **usage-check.sh**: one-shot formatted read of the 5-hour and 7-day windows for manual spot checks (usable by anyone; only arming is skill-gated).
- **CLAUDE.md**: documents the new skill.

Restructure the review architecture: consolidate ten reviewers into five grouped by reading mode, run the deep pass as sequential waves with fixes between them, and make the judge scan the fixes no reviewer saw. Finding IDs become meaningful slugs. Wall-clock time was deliberately traded away for token efficiency and outcome quality.

- **Reviewer consolidation (10 → 5).** Reviewers are now grouped by *reading mode*, not fine-grained topic — the attention-diffusion risk comes from mixing kinds of reading, not from rubric breadth:
  - **prepass-reviewer** (new, Sonnet) = slop-reviewer + scope-reviewer. Same two thin lanes (slop: diff-only LLM tells and face-of-diff problems; scope: log-vs-diff completeness + design-authorization, round-aware, with direct ESCALATE authority), one spawn.
  - **citizen-reviewer** (new, Opus) = quality-reviewer + reuse-reviewer + efficiency-reviewer. One long-term-owner reading: compare the diff against the codebase it has to live in.
  - **tracer-reviewer** (new, Opus) = correctness-reviewer + error-handling-reviewer + security-reviewer. One adversarial reading: trace the code, try to break it.
  - **test-reviewer** stays its own agent (it reads a different artifact) and moves from Sonnet to Opus.
  - Deleted: slop-, scope-, correctness-, security-, error-handling-, quality-, reuse-, efficiency-reviewer.
- **Deep review runs as two sequential waves with implementer fixes between them** (replacing the 7-way parallel fan): wave 1 `citizen-reviewer` → implementer responds/fixes → wave 2 `tracer-reviewer` + `test-reviewer` in parallel over the cumulative round diff (wave-1 fixes included — which is how wave-1's fixes get reviewed) → implementer responds/fixes → judge. Structural findings get fixed before the deep bug-hunt reads the code, duplicate findings across reviewers largely disappear, and waves stay blind to each other's notes (independent sampling beats iteration for diversity). Each wave writes its own dispositions doc: `dispositions-deep-r<R>-w<W>-a1.md`; the rework doc spans waves (`dispositions-deep-r<R>-a2.md`). Deep notes files: `notes-deep-{citizen,tracer,test}-r<R>.md`; prepass artifacts simplify to `notes-prepass-r<R>.md` / `escalation-prepass-r<R>.md`.
- **Judge: respond-commit regression scan.** The orchestrator now passes the deep judge the **reviewed HEAD** (the commit wave 2 saw); the judge scans `reviewed HEAD..HEAD` — the respond commits no reviewer reviewed — checking each fix holds on all paths and hunting for new breakage. Problems found there are disputed items like any other. New verdict-file section between the findings walk and disputed items; verdict header stays last.
- **TODO dispositions must self-score the judge's rubric.** The implementer's respond mode now requires every TODO(slug) disposition to answer the judge's two acceptability questions (worth doing? requires design/owner input first?) inline, with the warning that the judge re-scores and a Q2 failure gets bounced to do-it-now. Puts the anti-TODO-explosion bar in front of the agent tempted to punt, not just the one that catches it.
- **Finding IDs are slugs, not numbers**: `<category>-<short-kebab-slug>` (e.g. `security-toctou-user-record-update`) instead of `security-1`. IDs get quoted in commit messages and chat; the slug carries the meaning. Categories are the old lane vocabulary (`slop`, `scope`, `correctness`, `errhandling`, `security`, `test`, `quality`, `reuse`, `efficiency`, `requirements`, `design`, `code`) and map to lanes, not agents.
- **Lanes are not blinders.** Every reviewer now carries an "Out of lane" section replacing the old "Not your lane" referrals: work your own rubric first, but report a real problem you trip over outside it under whichever category fits, rather than staying silent because another specialist owns it.
- **Removed the orchestrator skill** (`skills/orchestrator/`) — it was a hand-maintained near-copy of the orchestrator agent and had already drifted (missing todo-burndown, SendMessage, parallel-spawn mechanics; disagreed on working-dir selection). The agent is the single source of truth.
- **/simplify** now spawns the single citizen-reviewer instead of three parallel reviewers.
- **implementer**: fixed duplicate step numbering in incremental mode; respond-mode inputs clarified for per-wave notes.
- **CLAUDE.md**, **READMEs**: rewritten for the new roster, wave flow, slug IDs, and artifact naming (round `r<R>` / wave `w<W>` / attempt `a<A>`).

### 0.12.0 — 2026-07-08

Re-pin the explorer and eli5-explainer for the opus-low ≈ sonnet-high cost/performance tradeoff (Opus at low effort is roughly the cost of Sonnet at high effort, with better results).

- **explorer**: moved from `model: sonnet` to `model: claude-opus-4-8[1M]` with `effort: low`. This is the first use of the `effort` frontmatter field on a review-chain agent; effort pins apply when the agent is active, overriding the session effort level but not the `CLAUDE_CODE_EFFORT_LEVEL` env var. (Note: `effort` can only be pinned in agent frontmatter — unlike `model`, there is no per-spawn effort parameter, so the `model-override` hook / `.conf` file cannot re-pin it locally.)
- **eli5-explainer**: added `effort: low` (model unchanged, `claude-opus-4-6[1M]`).
- **CLAUDE.md**, **README**: the explorer is now described as "Pinned to Opus at low effort"; the intercept-explore blurb's parenthetical for the `review-chain:explorer` agent now reads "(Opus)". The `Explore`-hook default upgrade target (Sonnet) is a separate mechanism and is unchanged.

### 0.11.0 — 2026-07-07

Stop overwriting review artifacts: they are the workflow's audit trail, so every review round and rework attempt now writes its own numbered file instead of clobbering the last.

- **orchestrator** (agent + skill): established the principle that workflow artifacts are the **audit trail of the workflow itself** — not ground truth for the current state of the code, but 100% ground truth for what the workflow did at each step — so review artifacts are **never overwritten**. Introduced a two-ordinal naming scheme keyed by **round `R`** (review pass for requirements/design, implementation round for pre-pass/deep — pre-pass and deep of a round share `R`) and **rework attempt `A`** (1 = initial, 2 = the one rework round): `notes-<phase>-<reviewer>-r<R>.md`, `dispositions-<phase>-r<R>-a<A>.md`, `judge-verdict-<phase>-r<R>-a<A>.md`, `escalation-<phase>-{scope,respond}-r<R>[-a<A>].md`. Every review phase (requirements-review, design-review, pre-pass, deep), both user-gate revision loops, and the ship-gate revision path now pass numbered targets; the orchestrator tracks `R` (incremented at each new implementation round and each post-gate re-review) and never writes to a path that already exists. User chat-directive files are numbered too (`notes-<phase>-user-r<R>.md`, `notes-shipgate-user-<K>.md`). A judge ESCALATE is the verdict file itself, so numbering the verdict preserves every REWORK/ESCALATE verdict. Added an **Audit trail** principle and a **Never** entry to both files.
- **implementer**, **scope-reviewer**: the two agents that hardcoded escalation filenames (`escalation-respond.md`, `escalation-prepass-scope.md`) now write to an orchestrator-supplied numbered escalation target (added to their Inputs).
- Unchanged by design: pre-freeze in-place editing of the four spec docs (`design.md` / `requirements.md` / `design-eli5.md`, including eli5 regeneration) and the append-only `implementation-log.md`.
- **CLAUDE.md**: documented the audit-trail / no-overwrite principle and the `r<R>`/`a<A>` naming scheme in the architecture section.

### 0.10.0 — 2026-07-07

Grow implementation increments to a 500–800 LOC target (they were coming out too small), and bar the explorer from spawning subagents.

- **implementer**: replaced the "as-small-as-reasonable / one semantic change" increment-scoping rubric — an increment is now **a coherent slice targeting 500–800 lines of code** (workflow artifacts and docs excluded). Dropped the atomicity tests that drove over-splitting: the "singular, not list-shaped" one-verb-one-object test, the "at most one design section" cap, and the "bulk of remaining work is a flag" language. New tests are **coherent, not a grab-bag** (joining distinct operations is fine when they share a through-line), **sized, not sprawling** (fold in adjacent work when well under ~500; split at a seam when well over ~800; targets, not hard limits), **independently coherent**, and **leaves the tree buildable**. Mid-flight guidance changed from reflexive "shrink" to "split only if ballooning well past the target." The round-of-5 review cadence is unchanged.
- **explorer**: now explicitly prohibited from spawning subagents (the `Agent`/`Task` tool) — it does all searching and reading in its own context. Stated in both the **Don't** list and the **Tool use** section.
- **CLAUDE.md**, **README**: the implementer one-liner now says "incremental slices" rather than "small increments."

### 0.9.0 — 2026-07-03

Make incremental the only implementation mode and review it in rounds — every 5 increments, with silent squashes between rounds and a human gate only at the end.

- **orchestrator** (agent + skill): removed single-shot ("initial") implementation. Implementation now always runs as **incremental rounds** — fresh `implementer` "incremental" spawns, one increment each, grouped into rounds of up to 5. A review round (pre-pass + deep) fires when the implementer replies `done` **or** the round hits its 5th increment. The orchestrator tracks a **round base** (the commit reviews diff against; the original base for round 1, then each intermediate squash) and an increment counter reset each round. A round reviews only `round base..HEAD`. When an **intermediate** round (5-cap, still `in progress`) clears the final judge, the orchestrator squashes that round's commits into one commit with **no user gate** and makes that squash the next round's base — which is why each round's reviews see only its own commits. Only the **final** round (implementer replied `done`) reaches the human ship-gate, which squashes all the way back to the original base after user approval. Freeze re-verification now also fires after each intermediate squash; Principles/Never amended so the "no squash without approval" rule binds the ship-squash only (intermediate squashes are automatic).
- **implementer**: dropped the `initial` mode entirely (incremental is the only implementation mode); promoted the clarification-needed handling to a top-level, all-mode section (it was nested under `initial`). Retired the separate **implementation report** — the append-only `implementation-log.md` is the single implementation record; `revise`/`respond` modes note deviations in the log or dispositions doc rather than a report. Incremental inputs now name the **round base**.
- **scope-reviewer**: made **round-aware**. Given a round type (intermediate | final), it holds the implementer to the **implementation log's claims for that round**, not the whole design — *unless* the round is the final `done` round, where the yardstick becomes the whole design checked against the full log (earlier rounds are squashed out of the diff, so it's a log-vs-design check). New **authorization** check every round: everything the log claims must trace to the **effective design (design + deltas)** — undesigned/undelta'd work is drift and gets flagged. Now receives the design deltas and the log in place of the retired report.
- **CLAUDE.md**, **README**: documented the incremental-rounds flow, the intermediate-squash-no-gate / final-round-ship-gate distinction, the log-as-record, and the round-aware scope-reviewer.

### 0.8.2 — 2026-07-03

Give the judge a code-owner's posture and let it propose concrete in-scope fixes.

- **judge**: new framing — **a code owner, not a lawyer**. Its interest is the true long-term health of the codebase and doing the right thing by it, not winning a procedural argument or clearing findings off a list. It pushes back when the responder takes the easy way out (partial fix, Won't-Do of convenience, a disposition satisfying the letter of a finding while leaving the code worse than an owner would accept), even where the finding as written undersold the problem — and doesn't manufacture work that doesn't serve the code.
- **judge**: on a disputed item, may now **propose a concrete fix design** for a problem still standing (e.g. a race patched on one path but not another), giving the responder something to build rather than only naming what's wrong. Hard-bounded: the proposal must stay within the approved design's scope and structure; a fix that would go well outside the original design is a design change → **ESCALATE**, not a verdict-smuggled redesign.

### 0.8.1 — 2026-07-02

Make the 0.8.0 comment-hygiene rule enforceable downstream — the implementer and judge now recognize it, so a "no such rule" Won't-Do no longer sails through.

- **implementer**: new **Comment hygiene** rule — proactively bars comments that reference workflow/design/ADR docs (`// per design.md §3`) or read as changelog (what the code *used to* do), and fixes the responder posture: such a reviewer finding is legitimate → disposition **Fixed**; the only valid Won't-Do is showing the comment doesn't actually reference an ephemeral doc / isn't changelog-style (reviewer misread), never "there is no such rule."
- **judge**: new **Comment hygiene** severity-calibration bullet — these findings are a standing project standard, not a reviewer invention; a Won't-Do resting on "there is no such rule" is invalid and the finding is should-fix, with Won't-Do holding only on a demonstrated reviewer misread.

### 0.8.0 — 2026-07-01

Teach the comment-hygiene reviewers to catch ephemeral-doc references, changelog-style comments, and verbosity.

- **slop-reviewer**: added three LLM-writing-tell bullets — **changelog comments** (describing what the code *used to* do / how it changed, e.g. `// no longer needs the lock`), **overly verbose comments** (paragraphs where a line would do), and **comments referencing design / ADR / workflow documents** (workflow design docs are ephemeral and must not be referenced from code; the code must stand on its own).
- **quality-reviewer**: added Catch #9 **Comment hygiene** carrying both criteria (ephemeral design/ADR/workflow-doc references; changelog/verbose comments), explicitly flagged as shared with the slop-reviewer rather than punted to it.

### 0.7.0 — 2026-06-26

Freeze the spec at implementation start; capture later revisions as append-only delta docs instead of in-place edits.

- **orchestrator** (agent + skill): new **freeze** step before the first `implementer` spawn — `exploration.md`, `requirements.md`, `design.md`, and `design-eli5.md` are committed (recorded as the `freeze` hash; checksummed instead in scratch/no-VCS working dirs) and become immutable. After **every** implementer commit (initial, increment, rework, ship-gate revision) the orchestrator re-verifies the frozen set is byte-unchanged (`git diff --quiet <freeze> -- …` or checksum re-check); any modification halts the workflow — restore from freeze, surface as a violation, re-route via a delta doc. New **spec deltas** step: post-freeze requirements/design changes go in new `requirements-delta-<N>.md` / `design-delta-<N>.md` docs that reference the original and record only the delta; effective spec = original + deltas in order, and every delta path travels downstream alongside the original. Rewired the two post-freeze change paths (clarification-needed during implement, ship-gate user revisions) to route through deltas; added matching Principles/Never entries, working-dir file names, and a post-freeze eli5 rule (`design-eli5-delta-<N>.md`, never overwriting the frozen eli5).
- **designer**, **requirements-refiner**: new **delta** mode (write a delta doc referencing the frozen original, recording only the change, calling out what it supersedes), with an explicit "revise = pre-freeze in-place / delta = post-freeze new doc" distinction.
- **implementer**: now told its effective spec is the design/requirements plus their deltas applied in order (a later delta supersedes what it overrides), and never to edit a frozen design/requirements/delta doc to resolve a finding.
- **CLAUDE.md**: documented the spec-freeze + delta mechanism and updated the designer/refiner role bullets.

### 0.6.0 — 2026-06-26

Make the explorer strictly context-only and give the orchestrator a dedicated troubleshooting path.

- **explorer**: now explicitly forbidden from diagnosing, troubleshooting, or root-causing — it gathers context and reports facts, never reaching conclusions, passing judgement, or solving problems. New top section instructs it to **politely decline a diagnostic/troubleshoot/root-cause request immediately, before any `Read`/`Grep`/`Bash`** (a refusal that follows investigation has already done the forbidden thing); mixed requests get the context gathered but no diagnosis/theory/fix. Added a matching **Don't** bullet and updated the intro line and frontmatter description.
- **orchestrator** (agent + skill): new **"Troubleshooting / root-cause requests"** section for "why is X broken / diagnose this" questions, which are outside the build workflow. Flow: (1) spawn `explorer` for a context-only exploration around the symptom (passed as scope to gather, not a question to answer); (2) **`Read` the explorer's full report into context** rather than relying on the ≤3-line reply summary; (3) **do the diagnostic reasoning itself** in the main conversation, reading source as needed, instead of delegating to a subagent — called out as the one place the orchestrator steps out of pure traffic-cop posture; (4) once root cause is found and the user wants a fix, route into the normal workflow.
- **CLAUDE.md**: explorer description updated to record the context-only constraint and the orchestrator's read-full-report-then-troubleshoot-itself path.

### 0.5.0 — 2026-06-21

Realign the requirements phase around the refiner's "better prompt, not a spec" mission: faithful most-intuitive interpretation, no design dictation, and open questions that are genuinely the user's to answer.

- **requirements-reviewer**: rubric reworked from a generic UX/sanity check into a "did the refiner do its job?" check. New/sharpened dimensions: **verbatim restatement** present and un-drifted; **most-intuitive interpretation** (flag lawyerly / pathological / contrived / surprising readings and reading in *more* than was asked); **clear and plain** + **scope fidelity**; **no design dictation** (folds in the old "enrichment-not-design" and "over-constraint" bullets, and now flags anything that even *suggests* a design path); **clarifying questions when warranted** (two or more genuinely-*likely* readings → should have asked) vs. **no pestering** (unlikely/pathological readings must not be raised); **open questions are the user's to answer** (wrong if a design question — all design is the design phase's job — or code-answerable — the refiner should have resolved it). Dropped the standalone "clean, least-surprise UX" bullet (UX-of-design belongs to the design-reviewer). Frontmatter description, intro, and process updated to match.
- **requirements-refiner**: now opens the doc with the user's **original request quoted verbatim** (no paraphrase/summary) — added to the voice guidance, the draft doc structure, and the too-ambiguous (CLARIFICATION-NEEDED) structure. "Resolve ambiguities" rewritten to take the **most intuitive reading** (don't over-interpret; only raise genuinely-likely, non-pathological alternatives as open questions). Open-questions definition tightened to matters of *intent or direction* only — not design questions, not code-answerable ones, not unlikely/pathological readings. **Sources** loosened: instead of punting gaps to the user as open questions, the refiner may read code (itself or via a subagent) when the exploration is incomplete or contradictory, and resolves code-answerable gaps itself.

### 0.4.0 — 2026-06-17

Add a second `PreToolUse` hook to re-pin agent models from local config / env vars, plus a `/configure-models` skill to set it up.

- **model-override** (new `PreToolUse` hook, `hooks/hooks.json` + `hooks/model-override.sh`): overrides the model an agent runs on without editing its agent file or publishing a new version. Fires on every `Agent`/`Task` spawn and resolves a model for the `subagent_type` by precedence (first hit wins): per-agent env var `REVIEW_CHAIN_MODEL_<AGENT>` (e.g. `REVIEW_CHAIN_MODEL_IMPLEMENTER=opus`), blanket `REVIEW_CHAIN_MODEL_ALL`, an explicit model the orchestrator already passed on the spawn (respected — config defers to it, env overrides it), then `./.claude/review-chain-models.conf` (project) and `~/.claude/review-chain-models.conf` (user). Strips the `review-chain:` spawn prefix so config keys are bare names; works for any `subagent_type`. Ignores `Explore` (owned by `intercept-explore`, which has the `deny` mode). Rewrites the tool input via `updatedInput`; fails open if `jq` is missing or input is unparseable.
- **configure-models** (new skill, `skills/configure-models/`): generates and optionally edits the local `review-chain-models.conf`. Wraps a deterministic template generator (`references/gen-model-config.sh`) that reads every agent's current model pin and writes a fully-commented config (all lines commented, so it overrides nothing until edited); supports `--project` / `--user` / stdout, refuses to clobber without `-f`, and locates the plugin's `agents/` dir by walking up from itself. The skill can also activate specific overrides on request (e.g. "set implementer to opus").
- **README** + **CLAUDE.md**: document the hook's precedence table, the config file format, and the `/configure-models` entry point.

### 0.3.0 — 2026-06-17

Rework requirements-refiner: enriched prompt instead of formal spec.

- **requirements-refiner**: rewritten to produce "a better prompt" — narrative prose that enriches the user's brief request with codebase context, resolves ambiguities, and flags tensions between the request and the codebase. No longer writes a formal specification with acceptance criteria and in-scope/out-of-scope sections. Output style mirrors the eli5-explainer: assumes no codebase knowledge, introduces concepts before using them, explains reasoning. Pinned to `claude-opus-4-6[1M]` (was `claude-opus-4-8[1M]`).
- **requirements-reviewer**: rubric updated to match — "requirements not design" → "enrichment not design", "over-specification" → "over-constraint", added "tensions missed or misrepresented" dimension.
- **design-reviewer**, **judge**: terminology updated ("requirements doc" → "refined request") where these agents reference the refiner's output.

### 0.2.1 — 2026-06-14

Loosen the orchestrator's working-dir guidance to defer to project documentation conventions.

- **orchestrator**: the `## Working dir` section no longer prescribes a fixed in-repo (`docs/designs/<slug>/`) vs scratch (`.claude/work/<slug>/`) choice — it now tells the orchestrator to follow the project's documentation standard if one exists (e.g., ADR dirs) and otherwise just create a workflow directory.

### 0.2.0 — 2026-06-14

Intercept built-in `Explore` agent spawns and upgrade them off Haiku.

- **intercept-explore** (new `PreToolUse` hook, `hooks/hooks.json` + `hooks/intercept-explore.sh`): the built-in `Explore` agent runs on Haiku, too weak for this workflow; the orchestrator should use `review-chain:explorer` (Sonnet) but reflexively reaches for `Explore`. The hook fires on every `Agent`/`Task` spawn but only acts when `subagent_type == "Explore"`, rewriting the tool input via `updatedInput`. Default behavior: silently override the model to `sonnet`. Configurable via the `REVIEW_CHAIN_EXPLORE_HOOK` env var — `off` (pass through to Haiku), `deny` (block and redirect to `review-chain:explorer`), or any model name. Fails open if `jq` is missing or input is unparseable.
- **README** + **CLAUDE.md**: document the hook, its env-var control surface, and the global-scope / no-native-toggle caveat.

### 0.1.17 — 2026-06-13

Stop instructing the models how to write, and add an ELI5 rendering of the design for the user gate.

- **All agents + skills**: removed the trailing `## Style` directive block (`Concise. Precise… No padding… Audience: smart LLM/human… Repeat note in all docs you author.`) and the stray inline style notes (explorer's "Concise ≠ sparse / token-dense", implementer's "Concise;" log instruction). The models write as they write; substantive guidance (e.g. explorer's "quote the signature over prose", test-reviewer's "LLM tests are often verbose + vacuous") is kept.
- **eli5-explainer** (new agent, pinned to `claude-opus-4-6[1M]`): after design review approves, renders the design as a no-context-assumed ELI5 narrative at `design-eli5.md` — builds all context step by step, explains every decision's reasoning, elides low-level detail, treats open questions thoroughly. Iron rule: explains the design, never deviates from it; surfaces gaps rather than fixing them. One-shot, not part of any review chain.
- **orchestrator** (agent + skill): new `eli5` stage between design-review and the design user gate; the gate now surfaces `design.md` and `design-eli5.md` together; the ELI5 is regenerated on any later design revision so the two stay in sync.

Revert 0.1.15: change all Fable 5 pins back to Opus 4.8.

### 0.1.15 — 2026-06-09

Change all Opus pins to Fable 5.

### 0.1.14 — 2026-05-28

Change all Opus pins to 4.8.

### 0.1.13 — 2026-05-21

Pin all agents to explicit model IDs instead of `inherit` or the bare `opus` alias.

- **designer**, **judge**, **requirements-refiner**, **requirements-reviewer**: pinned to `claude-opus-4-6[1M]`
- **code-reviewer**, **correctness-reviewer**, **design-reviewer**, **efficiency-reviewer**, **orchestrator**, **security-reviewer**: pinned to `claude-opus-4-7[1M]`

### 0.1.12 — 2026-05-15

Close the loop on requirements review: the refiner now responds to reviewer findings and the judge adjudicates, instead of dumping notes straight on the user. Same review → respond → adjudicate shape as every other phase.

- **requirements-refiner**: restructured into explicit `draft` / `revise` / `respond` modes mirroring the designer. New `respond` mode reads reviewer notes, fact-checks each finding against request + exploration, dispositions per finding as Fixed / TODO(slug) / Won't-Do, writes a dispositions doc. TODO(slug) in requirements means "promote to an Open-Questions entry under the slug" — surfaces to the user at the gate.
- **judge**: input list and process extended to recognize the requirements phase as a doc phase alongside design — reads the doc as ground truth, skips the code-phase TODOs walk. Header/verdict labels updated accordingly.
- **orchestrator** (agent + skill): requirements-review section gains responder + judge; user-gate now follows the same shape as the design gate (in-place edits → fresh refiner revise; notes / chat directives → fresh refiner respond → fresh judge; agent re-review opt-in). REWORK loop and ESCALATE surfacing mirror design. Workflow steps renumbered (was 6 → 33; now 6 → 37).

### 0.1.11 — 2026-05-15

Force the judge to write evidence before the verdict, with two worked examples to anchor the form. Was: judges routinely opened the verdict file with "Verdict: REWORK" or "Verdict: APPROVED" as the headline and then back-filled justification — pre-judging defeats the role.

- **judge**: `## Verdicts` replaced with `## Verdict file`. Opens with the rule "the verdict header is the last section of the file, never the headline." A 6-section file structure (Header → Added TODOs walk → Other findings walk → Disputed items → Approved → Verdict) replaces the prior "Verdict: X / one-line summary" template. Per-item assessment must follow per-item evidence; for any TODO, Q1 then Q2 each with brief evidence comes *before* the per-item assessment. The TODO walk is its own section and runs before the other-findings walk, matching the existing `## Process` step ordering. APPROVED / REWORK / ESCALATE definitions move under "Section 6: choosing the verdict" — they describe how to fill section 5/6 of the file, not peers of the structure. Reply-to-orchestrator formats consolidated into one subsection; the orphan `## Reply` section near the bottom removed.
- **judge**: `## TODO burndown mode` verdict structure flipped to match — Q1 + Q2 evidence per TODO before per-item verdict; count moved to the end.
- **judge**: new `## Output examples` section with two synthetic ICL examples (default-mode REWORK and todo-burndown). Both end with the verdict header, not start with it. Default-mode example contrasts a TODO that pins this-iteration code (must be do-now) against a TODO deferring a project-wide design call on pre-existing behavior (acceptable), so the rubric distinction is concrete.

### 0.1.10 — 2026-05-14

Force the judge to apply the TODO acceptability rubric *before* it reads dispositions, so responder rationale can't anchor the verdict.

- **judge**: `## Process` restructured into numbered subsections. New `### 2. Score added TODOs (code phase)` runs after the initial read pass and before the general finding walk. For every added TODO in the diff: FIRST apply the two-question rubric, THEN judge. Was: TODO rubric was a sub-bullet under "Disposition matches severity" in a single flat walk, so judges routinely formed a view of the disposition before applying the rubric and then retroactively justified. The renamed `### 3. Judge other findings` keeps a fallback TODO(slug) rule (FIRST score, THEN judge) for any TODO that slipped past step 2.

### 0.1.9 — 2026-05-14

New "TODO burndown" alternate workflow for chewing through accumulated TODOs without a current iteration to anchor scope.

- **orchestrator**: new `todo burndown (alternate entry)` workflow under `## Workflow`. Triggered by user request. Flow: explorer picks up to N (default 10) TODOs related semantically or by source location and builds context → `judge` mode `todo-burndown` produces per-item verdicts → user-approval gate routes batches into existing downstream workflows. Verdicts: `do-now` and `delete` items go to implementation-only (implementer → pre-pass → deep → ship-gate); `design` items re-enter the full workflow at `requirements`; `escalate` items go to the user out of band. Batches are combinable in one user direction. No judge round 2 — disputed verdicts get re-routed by the user, not re-judged.
- **judge**: new `## TODO burndown mode` section. Alternate role applying the existing two-question TODO acceptability rubric to a set of TODOs from an exploration doc; emits per-item verdicts `do-now` / `delete` / `design` / `escalate` instead of `APPROVED` / `REWORK` / `ESCALATE`. No responder, no dispositions, no diff. Explicitly disables the iteration-specific signals from the default mode ("this iteration created/worsened cannot be silently deferred"; "many TODOs in one phase → ESCALATE the pile") since burndown has no current iteration. Frontmatter description updated to flag the two modes.

### 0.1.8 — 2026-05-13

Tighter TODO acceptability: two-question rubric, no silent TODOs. Plus a new `check-todos` skill that applies the same rubric ad-hoc.

- **judge**: TODO acceptability section rewritten around two questions every TODO must answer YES to — (1) worth doing, now or eventually? (2) requires a design cycle or human review/input before doing? Clear NO to (1) → delete. Clear NO to (2) → do it now. Under uncertainty → ESCALATE for human/product-owner review rather than silently accept. Don't let the responder hide behind "non-trivial" — they must name design-work-required (→ TODO) or product-owner-input-needed (→ ESCALATE). Replaces the prior "defer-worthy / must-do" lists, which judges had been applying selectively. Sharpest rule preserved: a problem this iteration created or worsened cannot be silently deferred.
- **judge**: `TODO(slug)` bullet under "Disposition matches severity" now points at the two-question rubric instead of the old per-severity defer table.
- **check-todos** (new skill): ad-hoc audit of TODOs in the current diff against the same rubric. Default scope is TODOs added/touched in uncommitted changes + commits ahead of upstream. Classifies each as delete / do-now / escalate, then acts. Orchestrator mode delegates judgement to a `review-chain:judge` subagent and execution to an implementation subagent. User-facing convenience outside the orchestrator workflow.

### 0.1.7 — 2026-05-13

New `requirements-reviewer` agent + sharper judge guidance on what's TODO-eligible.

- **requirements-reviewer** (new, Opus): adversarial pre-design review of the requirements doc against the original request and the exploration report. Checks spirit-of-request fit, whether the project is a good idea at all, requirements-vs-design slippage, over-specification that constrains the designer, scope leakage in both directions, and big-picture sanity. Doesn't read code — takes the exploration at face value. No responder, no judge — notes surface straight to the user at the requirements gate.
- **orchestrator**: new `requirements-review` stage between `requirements` and the user gate. Runs after every refiner round that returns `READY-FOR-REVIEW`; skipped on `CLARIFICATION-NEEDED` (refiner's doc is questions). Findings prefix `requirements-N`. Workflow steps renumbered (6 → 33).
- **judge**: new `TODO acceptability` section formalizing the rule judges had been applying inconsistently. Defer-worthy: hypothetical perf at scale, pre-existing deficiency surfaced incidentally, in-scope work that would balloon the diff (with named blast radius). Must-do: defects/gaps/staleness this iteration introduced or worsened, tests for behavior added this iteration, low-hanging fruit, in-scope work generally. Non-trivial scope reduction (incl. "design underestimated effort") → ESCALATE, not TODO; TODO only after user approves the cut. Sharpest rule: a problem this iteration created or worsened cannot be deferred. Phase signal: many TODOs in one phase → consider ESCALATE rather than accept the pile.

### 0.1.6 — 2026-05-06

Close the "A + B + C in disguise" loophole in the incremental draft-scope rubric. Implementers were skirting the "no 'and' / commas" test by using numbered lists, bulleted lists, or "all four sections" framing to bundle multiple distinct operations into one increment.

- **implementer (incremental, step 2)**: first test renamed from "no 'and' / comma-list" to "Singular, not list-shaped" and generalized to catch list-shape *in any form* — "and" / commas, numbered list, bulleted list, "all four sections", "all the helpers", "everything in §3", "X + its tests + the Makefile wiring", "sections 1–4". List-shape is a semantic question, not a typographic one. If the draft can be rephrased as "do N things", N is the increment count.
- **implementer (incremental, step 2)**: self-check promoted from parenthetical to load-bearing prose in the step lead-in. "Draft → walk every test below against your own draft → if *any* trips, shrink and redraft → only then Edit." Plus the explicit observation that the most common rejection is shipping the first draft unchecked.

### 0.1.5 — 2026-05-03

Two more "small = one semantic change" tests for incremental draft scope, after observing implementers bundle eight design sections into one increment with the rationalization "this is the bulk of the remaining work."

- **implementer (incremental, step 2)**: two tests added to the existing list. (a) Touches at most one design section; two or more section numbers in the draft → multiple increments. (b) "Bulk of remaining work" / "rest of" / "finish off" / "wire it all up" is a flag, not a unit — either prove the remainder is genuinely atomic-indivisible, or pick one piece. Don't reach for the end just because the end is close.
- **implementer (incremental, step 2)**: existing "no 'and'" test clarified — "X and its tests" is fine (one change), "X and Y and Z and all their tests" is not.
- **implementer (incremental, step 2)**: tests now framed as a self-check — apply each to the draft before submitting the Edit; any fail → shrink and recheck.

### 0.1.4 — 2026-05-03

Plug a failure mode in incremental mode: implementer reports `done` on its increment scope (not the design), pre-pass scope-reviewer catches the gap, responder TODO-ifies the gap, deep review proceeds on a half-implementation. Three layers of defense in depth on the same case, plus a sharper `done` rubric.

- **implementer (incremental)**: rewrote the `done` rubric. Reply `done` iff the log accounts for **every design item** — implemented, or out-of-scope per design with TODO + rationale at the cited location. Trust the log without re-verifying against source. Anti-pattern called out: "I finished my increment, so I reply `done`." When in doubt, `in progress`. Was: implementers reading "done with `make check`" as "done with my slice".
- **implementer (respond)**: new scope-aggregate ESCALATE path. If `scope-N` findings together name *significant net new implementation*, neither Fixed (does real work in respond mode) nor TODO (retroactively narrows the design) is appropriate — write `escalation-respond.md` and reply `ESCALATE`. Bar is aggregate work, not finding count; trivial scope nits handled normally.
- **scope-reviewer**: direct ESCALATE authorization. If aggregate scope cuts are non-trivial, write `escalation-prepass-scope.md` alongside the findings file and reply `ESCALATE` — bypass the responder/judge chain entirely. Outermost layer of defense in depth.
- **judge**: severity calibration row for scope. `scope-N` dispositioned TODO when the missing work is non-trivial in aggregate → ESCALATE on round 1 (not REWORK). Powering through to deep review with material design omissions wastes review budget; needs human arbitration.
- **orchestrator**: pre-pass step 20 handles scope-reviewer `ESCALATE` reply (don't spawn responder, surface, stop). Pre-pass step 21 handles implementer respond `ESCALATE` reply (don't spawn judge, surface, stop). Resume only on user direction (typically: re-enter incremental, or revise design then re-implement).

### 0.1.3 — 2026-05-03

Prompt tuning after more field testing — user-feedback flow at human review gates, plus stronger reinforcement of parallel tool-call mechanics.

- **orchestrator**: explicit user-feedback flow at the design gate and ship-gate. Three forms — in-place artifact edits, separate notes doc, brief chat directives (orchestrator writes verbatim to file, numbered if multiple). After human review of a stage, agent re-review on revision is opt-in; user notes always travel to authors + reviewers + judge so agents cannot override user. New principle bullet covers the rule.
- **orchestrator**: `SendMessage` note — orchestrator must use `SendMessage` itself to relay messages to running subagents; cannot delegate.
- **orchestrator**: parallel batching now framed in literal token-level syntax. "Parallel = multiple `<invoke name="Agent">` blocks inside ONE `<function_calls>` block" with concrete shape example and a self-check ("count `invoke` blocks before sending"). Was: orchestrators (including Opus) routinely announced "spawning in parallel" then emitted one `Agent` block per turn.
- **all 16 non-orchestrator agents**: parallel-tool-calls reinforcement reframed to the same `<invoke>`-inside-`<function_calls>` framing. Replaces the prior "batch independent tool calls in one turn" wording.
- **implementer (incremental mode)**: steps 1–2 now lead with a literal `<function_calls>` block example showing turn 1 (parallel `Read`s of input docs) followed by turn 2 (single `Edit` appending draft scope). Anti-pattern callout names the failure mode — "grepping or reading source to 'orient' before the log Edit; the design IS your fully sufficient orientation for draft scope." Was: implementers reliably exploring source before writing draft scope.
- **orchestrator (incremental spawns)**: orchestrator must end every incremental implementer spawn prompt with a verbatim recency-reinforcement line; called out as the explicit exception to the no-rubric-restating rule.
- **README**: new "Using it (as a user)" section covering the three feedback forms, the gates that need explicit user approval, and that agent re-review post-user is opt-in.

### 0.1.2 — 2026-05-02

Prompt tuning after field testing.

- **orchestrator**: relay user-supplied subagent instructions verbatim — no elaboration or rephrasing.
- **orchestrator**: stronger batching language for independent subagent spawns. General "batch independent spawns into one assistant message" rule in `## Spawning`; pre-pass and deep-review steps now explicitly say "one assistant message, N `Agent` calls in parallel"; matching prohibition added to `## Never`. Was: orchestrator routinely serialized parallel reviewer fans.
- **implementer**: sharper definition of "small" for incremental-mode draft scope — one semantic change per increment, replacing the prior file-count guideline. Three concrete tests (one-sentence-no-"and", ship-half-still-coherent, multi-file-only-for-same-change).

### 0.1.1 — 2026-05-02

Token-efficiency pass on agent prompts after field-testing.

- **implementer**:
  - `incremental` mode: explicit first-turn gate — `Read` design + requirements + log in parallel; **no** source reads, `Grep`, or `ls` before a draft scope is written to the log.
  - `incremental` mode: draft scope is replaced with the shipped scope at the end of each increment.
  - `incremental` mode: added an example log entry showing the expected shape (file:line refs, flat bullets, deviations and TODOs inline) immediately followed by an explicit prohibition on "Remaining work" / "Next" / "Future work" sections.
  - `initial` mode: `Read` design + requirements in parallel on first turn.
  - New `Rules` bullet on batching independent tool calls per turn.
- All other authoring agents (designer, requirements-refiner, explorer), all reviewers, and the judge: new one-line `Tool use` section directing batched independent tool calls in a single turn. Orchestrator unchanged — it already batches reliably.

### 0.1.0 — 2026-05-02

Initial public release.

- Orchestrator agent — drives explore → refine → design → implement → review; spawns one-shot subagents, consumes only short summaries.
- Authoring agents: explorer, requirements-refiner, designer, implementer.
- Review specialists (one-shot per phase): slop, scope, error-handling, correctness, security, test, reuse, quality, efficiency, design, plus opt-in generalist code-reviewer.
- Judge agent — adjudicates dispositions against findings; APPROVED / REWORK / ESCALATE; one rework round per phase.
- Skills: `simplify` (parallel quality + reuse + efficiency review), `cleanup-editor` (self-edit pass for authors), `orchestrator` (slash-command entry).
- Disposition vocabulary: Fixed / TODO(slug) / Won't-Do.

## setup-project

### 0.1.0 — 2026-05-02

Initial public release.

- `setup-project` skill: writes TODO.md template, configures orchestrator as default agent, adds a generic Working-With-Claude-Code section to CLAUDE.md.
