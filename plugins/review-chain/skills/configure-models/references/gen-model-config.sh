#!/usr/bin/env bash
#
# review-chain — generate a per-agent model-override config template.
#
# Normally invoked via the /review-chain:configure-models skill, but runnable
# directly. Reads the model pin from every review-chain agent definition and
# emits a commented config file. Every agent line is commented out, so the file
# overrides nothing until you uncomment and edit a line. This keeps the
# template safe to regenerate and avoids pinning stale defaults.
#
# Usage:
#   gen-model-config.sh                # print template to stdout
#   gen-model-config.sh PATH           # write to PATH (won't overwrite)
#   gen-model-config.sh -f PATH        # write to PATH, overwriting
#   gen-model-config.sh [-f] --project # write ./.claude/review-chain-models.conf
#   gen-model-config.sh [-f] --user    # write ~/.claude/review-chain-models.conf
#   gen-model-config.sh -h             # show this help
#
# The generated file is read by hooks/model-override.sh. See that hook for the
# full precedence rules (env vars beat the project file beats the user file).

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Locate the plugin's agents/ dir by walking up from this script, so the
# template stays correct no matter where in the plugin tree the script lives.
AGENTS_DIR=""
d="$SCRIPT_DIR"
while [ "$d" != "/" ]; do
  if [ -d "$d/agents" ]; then AGENTS_DIR="$d/agents"; break; fi
  d=$(dirname "$d")
done

usage() {
  cat <<'USAGE'
gen-model-config.sh — dump a commented per-agent model-override config.

  gen-model-config.sh                # print template to stdout
  gen-model-config.sh PATH           # write to PATH (won't overwrite)
  gen-model-config.sh -f PATH        # write to PATH, overwriting
  gen-model-config.sh [-f] --project # write ./.claude/review-chain-models.conf
  gen-model-config.sh [-f] --user    # write ~/.claude/review-chain-models.conf
  gen-model-config.sh -h             # this help
USAGE
}

FORCE=0
if [ "${1:-}" = "-f" ] || [ "${1:-}" = "--force" ]; then
  FORCE=1
  shift
fi

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  --project) OUT="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/review-chain-models.conf" ;;
  --user)    OUT="$HOME/.claude/review-chain-models.conf" ;;
  "")        OUT="" ;;   # stdout
  *)         OUT="$1" ;;
esac

if [ -z "$AGENTS_DIR" ] || [ ! -d "$AGENTS_DIR" ]; then
  echo "gen-model-config: could not locate the review-chain agents/ dir above $SCRIPT_DIR" >&2
  exit 1
fi

emit() {
  cat <<'HEADER'
# review-chain per-agent model overrides.
#
# Format:   <agent-name> = <model>      e.g.  implementer = opus
# Wildcard: * = <model>                 applies to every review-chain agent
# A value of "inherit", "default", "-", or empty means "no override".
# Lines starting with "#" are ignored; uncomment one to activate it.
#
# Precedence (first hit wins), handled by hooks/model-override.sh:
#   1. env REVIEW_CHAIN_MODEL_<AGENT>   (e.g. REVIEW_CHAIN_MODEL_IMPLEMENTER=opus)
#   2. env REVIEW_CHAIN_MODEL_ALL
#   3. an explicit model the orchestrator already passed on the spawn
#   4. this file, when at ./.claude/review-chain-models.conf   (project)
#   5. this file, when at ~/.claude/review-chain-models.conf   (user)
#
# Note: the built-in Explore agent is controlled separately by the
# REVIEW_CHAIN_EXPLORE_HOOK env var (see hooks/intercept-explore.sh).

# Override every agent at once:
#* = opus

HEADER
  for f in "$AGENTS_DIR"/*.md; do
    [ -f "$f" ] || continue
    name=$(awk -F': *' '/^name:/ {print $2; exit}' "$f")
    model=$(awk -F': *' '/^model:/ {print $2; exit}' "$f")
    [ -n "$name" ] || continue
    printf '# %s — default: %s\n' "$name" "${model:-<unset>}"
    printf '#%s = \n\n' "$name"
  done
}

if [ -z "$OUT" ]; then
  emit
else
  if [ -e "$OUT" ] && [ "$FORCE" -ne 1 ]; then
    echo "gen-model-config: refusing to overwrite $OUT (use -f to force)" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$OUT")"
  emit > "$OUT"
  echo "gen-model-config: wrote $OUT" >&2
fi
