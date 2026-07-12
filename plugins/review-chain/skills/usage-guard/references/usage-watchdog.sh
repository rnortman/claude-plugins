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
# Tiers: 90 (mild), 95 (escalate), 98 (wind down). This process does NOT terminate on
# alert — it keeps running, and once the window rolls over it wakes the session with
# USAGE-RESET, then stays running to guard the new window (silent again until 90%).
#
# Poll cadence: (99 - utilization) minutes, clamped to [60s, 480s], so the 60s floor
# is only reached at 99% — be kind to the API. But whenever we are in ANY alert tier,
# each sleep is additionally capped so it never overshoots the window's nominal reset
# time + 45s. This is uniform across tiers on purpose: normal cadence still catches
# every tier crossing (you can't sleep through 95 or 98), and the reset+45 cap still
# lands a wake right after the real reset. USAGE-RESET fires only once we're at/after
# reset+45 AND the API confirms the roll (utilization dropped, or resets_at jumped a
# fresh window). The 45s cushion matters: the API can report the drop a few seconds
# early, and firing before the real reset just wakes the session back into the still-
# throttled old window.
#
# Env:
#   WATCHDOG_EXIT_ON_ALERT=1  exit after the first tier line (fallback mode for
#                             run_in_background, which only notifies on exit;
#                             the session must re-arm after each alarm). In this mode
#                             the reset-wait logic below never runs.
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

# ISO 8601 -> epoch seconds; echoes 0 if the timestamp is empty/unknown/unparseable.
to_epoch() {
  local iso="$1" e="" base off
  if [ -z "$iso" ] || [ "$iso" = "unknown" ]; then echo 0; return; fi
  e=$(date -d "$iso" +%s 2>/dev/null) || e=""          # GNU/coreutils: handles Z, frac, offsets
  if [ -z "$e" ] && [[ "$iso" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
    # BSD/macOS: normalize to a shape `date -j` accepts — the seconds field, then a
    # +HHMM offset, dropping any fractional seconds and mapping a bare `Z` to +0000.
    base="${BASH_REMATCH[1]}"
    off="+0000"
    [[ "$iso" =~ ([+-][0-9]{2}):?([0-9]{2})$ ]] && off="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
    e=$(date -j -f "%Y-%m-%dT%H:%M:%S%z" "${base}${off}" +%s 2>/dev/null) || e=""
  fi
  [ -z "$e" ] && e=0
  echo "$e"
}

fail_count=0
last_tier=0
# Nominal reset (epoch) of the window we're currently guarding — the boundary we're
# waiting to cross. Resynced to the live resets_at every idle poll (last_tier==0), but
# HELD FIXED for the whole time we're alerting, so a poll that lands after the roll but
# before boundary+45 can't overwrite it with the *new* window's reset time (which would
# make USAGE-RESET unreachable and freeze last_tier for the next window).
boundary_epoch=0

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
  # Treat a missing OR non-numeric utilization as an unreadable poll — a shape change
  # must not reach the arithmetic below and crash the loop silently under `set -u`.
  if [ -z "$util_raw" ] || ! [[ "$util_raw" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
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
  now=$(date +%s)
  reset_epoch=$(to_epoch "$resets")

  tier=0
  [ "$util" -ge 90 ] && tier=1
  [ "$util" -ge 95 ] && tier=2
  [ "$util" -ge 98 ] && tier=3

  if [ "$tier" -gt "$last_tier" ]; then
    case "$tier" in
      1) echo "USAGE-90: 5h usage at ${util}% (resets ${resets}). Set a cron wakeup for after reset NOW as insurance; keep working; prefer serial over parallel subagents." ;;
      2) echo "USAGE-95: 5h usage at ${util}% (resets ${resets}). If the cron wakeup is not set, set it NOW. Only launch subagent work that is strictly bounded and small." ;;
      3) echo "USAGE-98: 5h usage at ${util}% (resets ${resets}). Wind down now: checkpoint and end your turn. This watchdog stays running and will wake you with USAGE-RESET ~45s after the window resets; a cron wakeup as backup insurance is still wise." ;;
    esac
    last_tier=$tier
    # Lock in the boundary on first entry into alert if idle syncing never captured one
    # (e.g. the session started already above 90%).
    [ "$boundary_epoch" -eq 0 ] && [ "$reset_epoch" -gt 0 ] && boundary_epoch=$reset_epoch
    [ "$EXIT_ON_ALERT" = "1" ] && exit 0
  elif [ "$last_tier" -gt 0 ]; then
    # Reset detection, gated on being at/after the guarded window's nominal reset + 45s.
    if [ "$boundary_epoch" -gt 0 ]; then
      if [ "$now" -ge $((boundary_epoch + 45)) ] \
         && { [ "$util" -lt 50 ] || [ "$reset_epoch" -gt $((boundary_epoch + 300)) ]; }; then
        echo "USAGE-RESET: 5h window reset; usage now ${util}%. Normal operation may resume."
        last_tier=0
      fi
    elif [ "$util" -lt 50 ]; then
      # No parseable reset time — fall back to a bare utilization drop (can't time-gate).
      echo "USAGE-RESET: 5h window reset; usage now ${util}%. Normal operation may resume."
      last_tier=0
    fi
  fi

  # Resync the guarded boundary to the live reset time only while idle; hold it fixed
  # for the whole alert (including the iteration that just fired USAGE-RESET, which set
  # last_tier=0 above, so it re-captures the new window's reset here).
  [ "$last_tier" -eq 0 ] && [ "$reset_epoch" -gt 0 ] && boundary_epoch=$reset_epoch

  # Normal adaptive cadence...
  interval=$(( (99 - util) * 60 ))
  [ "$interval" -lt 60 ] && interval=60
  [ "$interval" -gt 480 ] && interval=480
  # ...but while alerting, never sleep past the nominal reset + 45s, so the next wake
  # lands right after the real reset (floor 30s if we're already past it and awaiting
  # a lagging roll). Applies at every tier, so tier crossings are never slept through.
  if [ "$last_tier" -gt 0 ] && [ "$boundary_epoch" -gt 0 ]; then
    to_reset=$(( boundary_epoch + 45 - now ))
    [ "$to_reset" -lt "$interval" ] && interval=$to_reset
    [ "$interval" -lt 30 ] && interval=30
  fi

  sleep "$interval"
done
