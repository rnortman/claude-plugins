# Changelog

Notable changes to plugins in this marketplace. Versions are per-plugin and follow [Semantic Versioning](https://semver.org/).

## review-chain

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
