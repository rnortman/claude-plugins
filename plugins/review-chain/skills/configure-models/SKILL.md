---
name: configure-models
description: Generate or edit local per-agent model overrides for review-chain agents (.claude/review-chain-models.conf) — re-pin a model without editing agent files or publishing.
---

Set up or adjust local model overrides for review-chain agents. The override hook (`hooks/model-override.sh`) reads the resulting config; changes take effect on the next agent spawn — no restart.

## Engine

The deterministic template generator is bundled at `references/gen-model-config.sh` (relative to this SKILL.md). Always produce the template via that script — never hand-write it. Resolve its absolute path from this skill's directory and run `bash <that-path> [args]`.

Script args: `--project` (write `./.claude/review-chain-models.conf`), `--user` (write `~/.claude/review-chain-models.conf`), `PATH` (write there), none (print to stdout). Prefix `-f` to overwrite an existing file.

## Steps

1. **Pick the target.** Default to `--project` unless the user asked for user-global (`--user`) or a specific path.

2. **Generate.** Run the script for that target.
   - If it refuses because the file already exists, do NOT blindly pass `-f`. Read the existing file, show the user its active (uncommented) lines, and only regenerate with `-f` if they want a fresh template — warn that it drops their current edits.

3. **Apply any specific overrides the user named.** If the user asked to set particular agents (e.g. "implementer to opus", "all the deep reviewers to opus", "everything on opus"), edit the written file: uncomment the matching `#agent = ` line and set the model. Use exact agent names as they appear in the file; a blanket request maps to the `* = <model>` line. If the user only wants the template to edit themselves, skip this.

4. **Report briefly.** Give the absolute path of the config file and list which overrides are now active. One-line reminders, only as relevant:
   - Commented lines are inactive; uncomment `agent = model` to activate.
   - Env vars win over the file: `REVIEW_CHAIN_MODEL_<AGENT>` and `REVIEW_CHAIN_MODEL_ALL` (e.g. `REVIEW_CHAIN_MODEL_IMPLEMENTER=opus`). The project file beats the user file. An explicit model the orchestrator already chose for a spawn is respected over the file.
   - Takes effect on the next agent spawn.
   - The built-in `Explore` agent is configured separately via `REVIEW_CHAIN_EXPLORE_HOOK`.
