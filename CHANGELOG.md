# Changelog

Notable changes to plugins in this marketplace. Versions are per-plugin and follow [Semantic Versioning](https://semver.org/).

## review-chain

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
