#!/usr/bin/env bash
# review-chain usage watchdog — long-running sensor + alarm for the 5-hour usage window.
#
# Run under the Monitor tool (persistent). Each line printed to stdout is delivered
# to the session as a wake-up event; empirically (2026-07) a Monitor event wakes a
# fully idle Claude Code session in ~10s, repeatedly, from one process.
#
# Data source: GET https://api.anthropic.com/api/oauth/usage with the OAuth bearer
# token from $CLAUDE_CONFIG_DIR/.credentials.json (falling back to ~/.claude).
# This is an UNDOCUMENTED endpoint (the one the CLI's own /usage view is fed from);
# response shape verified 2026-07-12: .five_hour.utilization (percent, float) and
# .five_hour.resets_at (ISO 8601). If it changes shape, this script disarms loudly
# rather than guessing.
#
# Tiers: 90 (mild), 95 (escalate), 98 (go to sleep — terminal, exits).
# Poll cadence: (99 - utilization) minutes, clamped to [60s, 480s], so the 60s
# floor is only reached at 99% — be kind to the API.
#
# Env:
#   WATCHDOG_EXIT_ON_ALERT=1  exit after the first tier line (fallback mode for
#                             run_in_background, which only notifies on exit;
#                             the session must re-arm after each alarm).
set -u

CONF="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CREDS="$CONF/.credentials.json"
ENDPOINT="https://api.anthropic.com/api/oauth/usage"
EXIT_ON_ALERT="${WATCHDOG_EXIT_ON_ALERT:-0}"
MAX_CONSECUTIVE_FAILURES=5

if [ ! -f "$CREDS" ]; then
  echo "WATCHDOG-DISARMED: no OAuth credentials at $CREDS (API-key session, or logged out). Usage monitoring unavailable; tell the user."
  exit 0
fi

fail_count=0
last_tier=0

while :; do
  token=$(jq -r '.claudeAiOauth.accessToken // empty' "$CREDS" 2>/dev/null)
  resp=""
  if [ -n "$token" ]; then
    resp=$(curl -sS --max-time 30 \
      -H "Authorization: Bearer $token" \
      -H "anthropic-beta: oauth-2025-04-20" \
      "$ENDPOINT" 2>/dev/null) || resp=""
  fi

  util_raw=$(jq -r '.five_hour.utilization // empty' <<<"$resp" 2>/dev/null)
  if [ -z "$util_raw" ]; then
    fail_count=$((fail_count + 1))
    if [ "$fail_count" -ge "$MAX_CONSECUTIVE_FAILURES" ]; then
      echo "WATCHDOG-DISARMED: could not read usage $fail_count times in a row (token expired? endpoint changed? network?). Usage monitoring is DOWN — do not assume headroom; tell the user."
      exit 0
    fi
    sleep 120
    continue
  fi
  fail_count=0

  util=${util_raw%.*}   # "38.0" -> "38"
  resets=$(jq -r '.five_hour.resets_at // "unknown"' <<<"$resp" 2>/dev/null)

  tier=0
  [ "$util" -ge 90 ] && tier=1
  [ "$util" -ge 95 ] && tier=2
  [ "$util" -ge 98 ] && tier=3

  if [ "$tier" -gt "$last_tier" ]; then
    case "$tier" in
      1) echo "USAGE-90: 5h usage at ${util}% (resets ${resets}). Set a cron wakeup for after reset NOW as insurance; keep working; prefer serial over parallel subagents." ;;
      2) echo "USAGE-95: 5h usage at ${util}% (resets ${resets}). If the cron wakeup is not set, set it NOW. Only launch subagent work that is strictly bounded and small." ;;
      3) echo "USAGE-98: 5h usage at ${util}% (resets ${resets}). Go to sleep now: checkpoint, confirm the wakeup is scheduled, end your turn." ;;
    esac
    last_tier=$tier
    [ "$tier" -eq 3 ] && exit 0
    [ "$EXIT_ON_ALERT" = "1" ] && exit 0
  elif [ "$last_tier" -gt 0 ] && [ "$util" -lt 50 ]; then
    echo "USAGE-RESET: 5h window reset; usage now ${util}%. Normal operation may resume."
    last_tier=0
  fi

  interval=$(( (99 - util) * 60 ))
  [ "$interval" -lt 60 ] && interval=60
  [ "$interval" -gt 480 ] && interval=480
  sleep "$interval"
done
