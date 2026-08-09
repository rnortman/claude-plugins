#!/usr/bin/env bash
#
# review-chain PreToolUse hook — rewrites the spawn input for every agent
# except the built-in Explore. Two independent policies share this one hook:
#
#   * model override    — re-pin the spawned agent's model from local config
#                         and/or env vars, without editing agent files or
#                         publishing a new plugin version.
#   * background policy — force review-chain agent spawns to run in the
#                         background so the parent is notified on completion
#                         instead of blocking.
#
# They live together because a PreToolUse hook's `updatedInput` REPLACES the
# whole tool input and the last hook to answer wins — the harness hands every
# hook the original input and never chains them. Two hooks each returning
# `updatedInput` for the same spawn would silently clobber each other, so a
# spawn gets exactly one hook that rewrites it. Explore spawns are the other
# side of that split and belong to intercept-explore.sh; this hook ignores
# subagent_type == "Explore".
#
# MODEL RESOLUTION — first hit wins:
#
#   1. env  REVIEW_CHAIN_MODEL_<AGENT>   per-agent override (highest)
#   2. env  REVIEW_CHAIN_MODEL_ALL       blanket override for every agent
#   3. an explicit model already on the spawn (the orchestrator's deliberate
#      choice) -> respected. Config below defers to it; the env vars above
#      override it.
#   4. $CLAUDE_PROJECT_DIR/.claude/review-chain-models.conf   (project)
#   5. ~/.claude/review-chain-models.conf                     (user)
#   (none) -> the model is left alone; the agent's frontmatter pin governs.
#
# <AGENT> is the agent name upper/snake-cased: requirements-refiner ->
# REVIEW_CHAIN_MODEL_REQUIREMENTS_REFINER. The "review-chain:" spawn prefix is
# stripped before lookup, so config keys are bare names (implementer, designer).
# The hook works for any subagent_type, but only review-chain agents ship a
# generated config template (skills/configure-models/references/).
#
# Config file format: one "agent = model" per line; "#" comments and blank
# lines ignored; inline "# ..." after a value ignored. A "* = model" line
# applies to every agent. A value of "inherit", "default", "-", or empty means
# "no override".
#
# BACKGROUND POLICY — applies only to subagent_type values prefixed
# "review-chain:", so built-in and third-party agents keep harness defaults:
#
#   REVIEW_CHAIN_BACKGROUND_HOOK
#     (unset / empty) -> default: force run_in_background = true
#     off | 0 | false | disable | none
#                     -> leave run_in_background alone
#     sync            -> force run_in_background = false (every spawn blocks)
#
# Recent Claude Code builds already background subagents by default, so the
# value here is pinning the behavior: an agent that explicitly passes
# run_in_background=false gets overridden either way. CLAUDE_CODE_DISABLE_-
# BACKGROUND_TASKS wins over this hook — when it is set the harness drops
# run_in_background from the Agent schema entirely and the policy is skipped.
#
# Fail-open: any parse error or missing jq -> do nothing, never block work.

set -u

# Fail open if jq isn't installed.
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
case "$TOOL" in
  Agent|Task) ;;
  *) exit 0 ;;
esac

SUBAGENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null) || exit 0
[ -n "$SUBAGENT" ] || exit 0
# Explore is owned by intercept-explore.sh.
[ "$SUBAGENT" = "Explore" ] && exit 0

# Bare agent key (strip the "review-chain:" spawn prefix) and its env-var form.
KEY=${SUBAGENT#review-chain:}
ENVKEY=$(printf '%s' "$KEY" | tr '[:lower:]' '[:upper:]' | tr -c '[:alnum:]' '_')
ENVKEY=${ENVKEY%_}   # drop a trailing _ left by a non-alnum final char

# ---------------------------------------------------------------- model ----

MODEL=""

# 1. per-agent env var
PERAGENT="REVIEW_CHAIN_MODEL_${ENVKEY}"
if [ -n "${!PERAGENT:-}" ]; then
  MODEL=${!PERAGENT}
fi

# 2. blanket env var
if [ -z "$MODEL" ] && [ -n "${REVIEW_CHAIN_MODEL_ALL:-}" ]; then
  MODEL=${REVIEW_CHAIN_MODEL_ALL}
fi

# 3. explicit model already on the spawn: with no env override, respect the
#    orchestrator's deliberate choice and skip the config lookup. The spawn is
#    still rewritten if the background policy has something to say.
DEFER_TO_SPAWN=0
if [ -z "$MODEL" ]; then
  EXPLICIT=$(printf '%s' "$INPUT" | jq -r '.tool_input.model // empty' 2>/dev/null) || EXPLICIT=""
  [ -n "$EXPLICIT" ] && DEFER_TO_SPAWN=1
fi

# 4 & 5. config files: project then user.
lookup() {
  # $1 = file, $2 = key; prints the model value (if any).
  awk -F= -v k="$2" '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
      key = $1
      sub(/^[[:space:]]+/, "", key); sub(/[[:space:]]+$/, "", key)
      if (key == k) {
        val = substr($0, index($0, "=") + 1)
        sub(/[[:space:]]+#.*/, "", val)
        sub(/^[[:space:]]+/, "", val); sub(/[[:space:]]+$/, "", val)
        print val
        exit
      }
    }' "$1" 2>/dev/null
}

if [ -z "$MODEL" ] && [ "$DEFER_TO_SPAWN" -eq 0 ]; then
  for CFG in "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/review-chain-models.conf" \
             "$HOME/.claude/review-chain-models.conf"; do
    [ -f "$CFG" ] || continue
    val=$(lookup "$CFG" "$KEY")
    [ -z "$val" ] && val=$(lookup "$CFG" '*')
    if [ -n "$val" ]; then MODEL=$val; break; fi
  done
fi

# Normalize the "no override" sentinels.
case "$MODEL" in
  inherit|default|-) MODEL="" ;;
esac

# ----------------------------------------------------------- background ----

# "" = leave alone, "true"/"false" = force that value.
BACKGROUND=""

case "$SUBAGENT" in
  review-chain:*)
    # The harness drops run_in_background from the Agent schema when background
    # tasks are disabled; injecting it there would be a lie, not an override.
    if [ -z "${CLAUDE_CODE_DISABLE_BACKGROUND_TASKS:-}" ]; then
      case "${REVIEW_CHAIN_BACKGROUND_HOOK:-on}" in
        off|OFF|0|false|disable|none) BACKGROUND="" ;;
        sync|SYNC)                    BACKGROUND="false" ;;
        *)                            BACKGROUND="true" ;;
      esac
    fi
    ;;
esac

# ---------------------------------------------------------------- emit -----

# Nothing to say if the spawn already carries the value we'd force.
if [ -n "$BACKGROUND" ]; then
  # Not `// empty` — jq's alternative operator swallows a literal false, which
  # is exactly the value sync mode needs to recognize as already-set.
  CURRENT=$(printf '%s' "$INPUT" | jq -r '
    if (.tool_input | has("run_in_background"))
    then (.tool_input.run_in_background | tostring)
    else "" end' 2>/dev/null) || CURRENT=""
  [ "$CURRENT" = "$BACKGROUND" ] && BACKGROUND=""
fi

[ -z "$MODEL" ] && [ -z "$BACKGROUND" ] && exit 0

UPDATED=$(printf '%s' "$INPUT" | jq -c --arg m "$MODEL" --arg bg "$BACKGROUND" '
  .tool_input
  | (if $m  != "" then .model = $m else . end)
  | (if $bg != "" then .run_in_background = ($bg == "true") else . end)
') || exit 0

# A model override keeps the historical "allow" — re-pinning a model is the
# operator's deliberate instruction and shouldn't then stop for a prompt. The
# background policy alone returns updatedInput with no permissionDecision: the
# harness still applies the rewrite, and the spawn faces the permission rules
# it would have faced anyway.
jq -nc --argjson ui "$UPDATED" --arg m "$MODEL" --arg bg "$BACKGROUND" --arg a "$SUBAGENT" '
  [ (if $m  != "" then "model -> " + $m else empty end),
    (if $bg != "" then "run_in_background -> " + $bg else empty end) ]
  | join(", ") as $why
  | {
      hookSpecificOutput: ({
        hookEventName: "PreToolUse",
        permissionDecisionReason: ("review-chain: " + $why + " for " + $a),
        updatedInput: $ui
      } + (if $m != "" then {permissionDecision: "allow"} else {} end))
    }'
exit 0
