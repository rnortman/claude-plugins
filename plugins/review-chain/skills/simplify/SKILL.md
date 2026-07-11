---
name: simplify
description: Review changed code for reuse, quality, efficiency; fix issues found.
---

Review changed files + fix issues. User-facing convenience for ad-hoc review outside the orchestrator.

## Phase 0: Working dir

Create `.claude/work/simplify/`. Use for the notes file.

## Phase 1: Review

Spawn `citizen-reviewer` — long-term-owner review across quality (hacky patterns, complexity, observability gaps, workarounds), reuse (duplicated functionality), and efficiency (performance, wasteful patterns). The agent finds changed code itself — don't `git diff` yourself, don't pass the diff.

Prompt: "Review current changes. Target notes: `.claude/work/simplify/citizen-notes.md`. Write to file. Reply path only."

Rubric baked in.

## Phase 2: Fix

Read the notes file at the returned path. Fix each finding directly. False positive or not worth addressing → skip; don't argue.

## Phase 3: TODOs for out-of-scope

Findings pointing to real problems in surrounding code that are out of scope for current change? Skipped findings representing genuine technical debt? Per item: add a TODO comment per project convention. Don't let out-of-scope issues vanish silently. Long-term ownership: leave the codebase better than you found it.

Done: brief summary of what was fixed + TODOs created (or confirm code was already clean).
