---
name: check-todos
description: Audit TODOs against the two-question rubric — eliminate, do-now, or surface to user. No silent TODOs.
---

Audit TODOs added in the current iteration.

## Rubric

Every TODO must answer YES to BOTH:

1. Worth doing, now or eventually?
2. Requires a design cycle or human review/input before doing?

Explore the code yourself to answer. Outcomes:

- Clear NO to (1) — not worth doing or actively harmful: Delete.
- Clear NO to (2) — doable now without further input: Do it now.

Under uncertainty: lean toward surfacing now for human/product owner review by escalating.

Furthermore: **a problem this iteration created or worsened cannot be silently deferred** — This must be fixed or escalated for visibility.

## Scope

Default: TODOs added or touched in the current diff (uncommitted + commits ahead of upstream/main).

Consult project standards for how to identify TODOs (e.g., TODO.md or other convention).

## Procedure

If operating in orchestrator mode, use a subagent to perform the judgement work (e.g., a review-chain:judge). Surface any escalation or uncertainty to the user if needed. Otherwise use an implementation subagent to execute the decision(s), and then normal code review afterward.
