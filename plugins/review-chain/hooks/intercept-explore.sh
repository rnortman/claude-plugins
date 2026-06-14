#!/usr/bin/env bash
#
# review-chain PreToolUse hook — intercept built-in "Explore" agent spawns.
#
# The built-in Explore agent runs on Haiku, which is too weak for this
# workflow's exploration. The orchestrator is meant to spawn the
# review-chain:explorer agent (Sonnet) instead, but reflexively reaches for
# Explore anyway. This hook intercepts those spawns and, by default, quietly
# upgrades them to Sonnet.
#
# Scope: fires on every Agent (subagent) spawn while review-chain is enabled,
# but only ACTS when subagent_type == "Explore". Every other tool call and
# every other agent passes through untouched.
#
# Behavior is controlled entirely by one environment variable:
#
#   REVIEW_CHAIN_EXPLORE_HOOK
#     (unset / empty) -> default: silently override Explore's model to sonnet
#     off | 0 | false | disable | none
#                     -> do nothing; the built-in Explore runs as-is (Haiku)
#     deny            -> block the spawn and tell Claude to use
#                        review-chain:explorer instead
#     <model>         -> override Explore's model to <model>, e.g. "opus",
#                        "haiku", or a full id like "claude-opus-4-8"
#
# There is no native per-plugin hook toggle in Claude Code, so this env var is
# the intended escape hatch: `export REVIEW_CHAIN_EXPLORE_HOOK=off` in any
# shell/project where you don't want it.
#
# Fail-open: if jq is unavailable or the input can't be parsed, the hook does
# nothing and the tool call proceeds unmodified — it never blocks work because
# of its own error.

set -u

# Fail open if jq isn't installed.
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
SUBAGENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null) || exit 0

# Only act on Explore-agent spawns. "Agent" is the current tool name; "Task" is
# the legacy alias. Anything else passes through untouched.
case "$TOOL" in
  Agent|Task) ;;
  *) exit 0 ;;
esac
[ "$SUBAGENT" = "Explore" ] || exit 0

MODE=${REVIEW_CHAIN_EXPLORE_HOOK:-sonnet}

case "$MODE" in
  off|OFF|0|false|disable|none)
    # Disabled: let the built-in Explore run as-is.
    exit 0
    ;;
  deny|DENY)
    jq -nc '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: "The built-in Explore agent runs on Haiku and is too weak for this workflow. Spawn the review-chain:explorer agent instead (Agent tool, subagent_type: \"review-chain:explorer\")."
      }
    }'
    exit 0
    ;;
  *)
    # Treat MODE as a model name and override Explore to run on it.
    UPDATED=$(printf '%s' "$INPUT" | jq -c --arg m "$MODE" '.tool_input + {model: $m}') || exit 0
    jq -nc --argjson ui "$UPDATED" --arg m "$MODE" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        permissionDecisionReason: ("review-chain: upgraded built-in Explore agent to model " + $m),
        updatedInput: $ui
      }
    }'
    exit 0
    ;;
esac
