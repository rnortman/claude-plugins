# Changelog

Notable changes to plugins in this marketplace. Versions are per-plugin and follow [Semantic Versioning](https://semver.org/).

## review-chain

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
