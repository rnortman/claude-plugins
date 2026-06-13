---
name: simplify
description: Review changed code for reuse, quality, efficiency; fix issues found.
---

Review changed files + fix issues. User-facing convenience for ad-hoc review outside the orchestrator.

## Phase 0: Working dir

Create `.claude/work/simplify/`. Use for the three notes files.

## Phase 1: Parallel reviewers

Single message, three Agent calls in parallel. Each agent finds changed code itself — don't `git diff` yourself, don't pass the diff.

1. `reuse-reviewer` — duplicated functionality. Target: `.claude/work/simplify/reuse-notes.md`.
2. `quality-reviewer` — hacky patterns, complexity, observability gaps, workarounds. Target: `.claude/work/simplify/quality-notes.md`.
3. `efficiency-reviewer` — performance, wasteful patterns. Target: `.claude/work/simplify/efficiency-notes.md`.

Prompt for each: "Review current changes. Target notes: `<path>`. Write to file. Reply path only."

Rubrics baked in.

## Phase 2: Fix

Wait for all three. Read the notes files at returned paths. Fix each finding directly. False positive or not worth addressing → skip; don't argue.

## Phase 3: TODOs for out-of-scope

Findings pointing to real problems in surrounding code that are out of scope for current change? Skipped findings representing genuine technical debt? Per item: add a TODO comment per project convention. Don't let out-of-scope issues vanish silently. Long-term ownership: leave the codebase better than you found it.

Done: brief summary of what was fixed + TODOs created (or confirm code was already clean).
