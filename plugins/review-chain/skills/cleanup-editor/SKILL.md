---
name: cleanup-editor
description: Self-edit a draft for clarity, contradictions, answerable open questions. Use after initial draft.
---

Just wrote a draft? Run yourself through this pass before handing off. Goal: clean linear story — final claims direct, contradictions resolved, open questions either answered or genuinely user-judgment.

Edit the draft in place.

## Find + fix

### Thought-process prose

Doc narrates your deliberation ("I considered X, then realized Y, but then thought about Z and decided…") instead of stating the final plan. Rewrite as "here is what we will do." Reader doesn't need the path.

### "But wait" / "actually" reversals

Mid-prose stream-of-consciousness reversals where you discover your error and correct mid-paragraph. Drop the wrong half, keep the correct claim. Correct answer not obvious from surrounding text → contradiction (next item) — investigate, don't just delete.

### Contradictions between sections

Section A says X; section B says ¬X. Find the truth (re-read code/spec/prior section). Rewrite both to agree. Don't paper over by hedging both — pick the right answer.

### Open questions you can answer

Draft poses a question that investigation would resolve — read a file, grep, check schema, look up an API. Investigate, answer, update doc. Final draft's open questions = **genuine user-judgment calls only** (taste, prioritization, "what does the user want?"). Anything answerable through investigation is your job.

### Terminology drift

Same concept named two ways. Pick one, normalize. Can't tell if they mean the same thing → contradiction → investigate.

### Promised but missing sections

Outline / earlier section promises something the doc doesn't deliver ("we'll cover X below…" with no X). Either write the content or remove the promise.

### Speculative / unverified claims

"I think this should…", "probably this means…". Matters? Verify. Doesn't matter? Cut.

### Filler

Throat-clearing intros, restated context the reader already has, "as mentioned above" cross-references earning nothing. Cut.

## Preserve

- All substantive technical content. Don't trim detail to shorten — only trim process narration, redundancy, filler.
- Genuine user-judgment open questions.
- Any "Human-review delta" block explaining what changed since user last read.
- Domain terminology + your authorial voice on substance.

## Operate

1. Re-read draft top to bottom.
2. Per issue: prose (rewrite in place) or substance (investigate + resolve)?
3. Do prose edits.
4. Do substance work — read what you need, update with the answer.
5. Done: no thought-process prose, no contradictions, no answerable open questions, no promised-but-missing sections.

You're not creating a separate cleanup report. Improve your own draft directly.

## Style

Concise. Precise. Complete. Unambiguous. No preamble. No padding. No obvious-statements. Audience: smart LLM/human.
