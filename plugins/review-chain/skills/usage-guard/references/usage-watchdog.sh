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
# .five_hour.resets_at (ISO 8601).
#
# Failure posture: TENACIOUS. API outages lasting hours are routine, so unreadable
# polls never make this script give up — it keeps retrying forever. What IS
# strictly rate-limited is talking to the session about it (each stdout line wakes
# the session and costs LLM tokens): one WATCHDOG-DEGRADED line after
# DEGRADED_AFTER_FAILURES consecutive failures, then a re-notice at most every
# DEGRADED_RENOTIFY_SECS while the outage continues, then one WATCHDOG-RECOVERED
# line when polling works again. The session owns the kill switch — it runs this
# script under the Monitor tool and can terminate it at any time if monitoring is
# no longer worth the wake-ups.
#
# Tiers: 90 (mild), 94 (escalate), 97 (wind down). Once utilization reaches 90%, the
# watchdog wakes the session on EVERY integer-percent increase (90, 91, 92, ...), not
# just tier crossings — the message body is tier-based, but the session gets to watch
# usage tick up (two parallel sessions can burn the tail of a window fast). This
# process does NOT terminate on alert — it keeps running, and once the window rolls
# over it wakes the session with USAGE-RESET, then stays running to guard the new
# window (silent again until 90%).
#
# Poll cadence: (99 - utilization) minutes, clamped to [60s, 480s], so the 60s floor
# is only reached at 99% — be kind to the API. While in ANY alert tier the cadence is
# further capped at 120s, so per-percent ticks are actually observed rather than
# batched into one multi-percent jump, and each sleep is additionally capped so it
# never overshoots the window's nominal reset time + RESET_CONFIRM_CUSHION_SECS.
#
# USAGE-RESET is guarded twice, because the API rolls before the new window is usable:
#   1. The roll is not BELIEVED until we're at/after reset+RESET_CONFIRM_CUSHION_SECS
#      AND the API confirms it (utilization dropped, or resets_at jumped a fresh
#      window) — the API can report the drop a few seconds early.
#   2. The roll is not ANNOUNCED until a further RESET_SETTLE_SECS have passed —
#      empirically there is a lag between the API reporting 0% and requests actually
#      being accepted in the new window.
# Firing early is the expensive failure: it wakes the session back into the still-
# throttled old window, and the wake-up is wasted.
#
# Env:
#   WATCHDOG_EXIT_ON_ALERT=1  exit after the first alarm (or degraded) line —
#                             fallback mode for run_in_background, which only
#                             notifies on exit; the session must re-arm after each
#                             alarm. In this mode the reset-wait logic never runs.
set -u

CONF="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CREDS="$CONF/.credentials.json"
ENDPOINT="https://api.anthropic.com/api/oauth/usage"
EXIT_ON_ALERT="${WATCHDOG_EXIT_ON_ALERT:-0}"
# Consecutive unreadable polls before the first WATCHDOG-DEGRADED line. Short
# blips (a failure or two between good polls) are absorbed silently.
DEGRADED_AFTER_FAILURES=5
# Minimum seconds between degraded re-notices while an outage continues. Each
# notice wakes the session (LLM tokens are expensive) — keep these rare.
DEGRADED_RENOTIFY_SECS=1800
# Retry cadence while polls are failing, as an exponential backoff from FAIL_RETRY_SECS
# doubling to FAIL_RETRY_MAX_SECS. A flat retry is actively harmful here: 120s is FASTER
# than the 480s steady-state cadence, so a rate-limited poll would make us poll harder.
# The endpoint is shared with the CLI's own /usage view and with any other session's
# watchdog on this account, so a 429 means the account bucket is hot — back off.
FAIL_RETRY_SECS=120
FAIL_RETRY_MAX_SECS=1800
# Cushion past the window's nominal reset before the API's roll is even believed. The
# API can report the drop a few seconds early.
RESET_CONFIRM_CUSHION_SECS=45
# Settle delay AFTER the roll is confirmed, before USAGE-RESET reaches the session.
# The API reports 0% before the new window actually accepts requests, so a session
# woken the instant utilization drops sends its first request into the old window and
# gets throttled. Waiting costs one minute; firing early costs the wake-up entirely.
RESET_SETTLE_SECS=60

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
# Outage bookkeeping: when the current failure streak started, whether the session
# has been told about it, and when it was last told (for re-notice rate-limiting).
first_fail_epoch=0
degraded_notified=0
last_degraded_notice=0
# Current retry interval; doubles per consecutive failure, reset on a good poll.
fail_retry=$FAIL_RETRY_SECS
last_tier=0
# Highest integer utilization already announced this window; a new alarm fires
# whenever current utilization exceeds it (and is >= 90). Reset on USAGE-RESET.
last_notified_util=0
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

  # Explicit API errors (rate_limit_error, authentication_error, ...) are unreadable polls
  # too, but we can say WHY in the degraded line instead of guessing.
  api_err=$(jq -r '.error.type // empty' <<<"$resp" 2>/dev/null)
  util_raw=""
  [ -z "$api_err" ] && util_raw=$(jq -r '.five_hour.utilization // empty' <<<"$resp" 2>/dev/null)
  # Treat a missing OR non-numeric utilization as an unreadable poll — a shape change
  # must not reach the arithmetic below and crash the loop silently under `set -u`.
  if [ -z "$util_raw" ] || ! [[ "$util_raw" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    now=$(date +%s)
    fail_count=$((fail_count + 1))
    [ "$first_fail_epoch" -eq 0 ] && first_fail_epoch=$now
    # Never give up — API outages lasting hours are routine. Keep retrying, but
    # rate-limit what reaches the session: first notice after the streak clears
    # DEGRADED_AFTER_FAILURES, then at most one re-notice per DEGRADED_RENOTIFY_SECS.
    if [ "$fail_count" -ge "$DEGRADED_AFTER_FAILURES" ] \
       && [ $((now - last_degraded_notice)) -ge "$DEGRADED_RENOTIFY_SECS" ]; then
      blind_min=$(( (now - first_fail_epoch) / 60 ))
      why="API outage? expired token?"
      [ -n "$api_err" ] && why="API returned $api_err"
      echo "WATCHDOG-DEGRADED: could not read usage for ~${blind_min}min ($fail_count consecutive failures — $why). Monitoring is BLIND — do not assume headroom. I keep retrying (backing off, currently every ${fail_retry}s) and will send WATCHDOG-RECOVERED when readings resume; further degraded notices are rate-limited to one per $((DEGRADED_RENOTIFY_SECS / 60))min. If you no longer need usage monitoring, kill this monitor."
      degraded_notified=1
      last_degraded_notice=$now
      [ "$EXIT_ON_ALERT" = "1" ] && exit 0
    fi
    sleep "$fail_retry"
    # Exponential backoff, capped — a struggling or rate-limiting endpoint must not be
    # polled harder than a healthy one.
    fail_retry=$(( fail_retry * 2 ))
    [ "$fail_retry" -gt "$FAIL_RETRY_MAX_SECS" ] && fail_retry=$FAIL_RETRY_MAX_SECS
    continue
  fi
  if [ "$degraded_notified" -eq 1 ]; then
    blind_min=$(( ($(date +%s) - first_fail_epoch) / 60 ))
    echo "WATCHDOG-RECOVERED: usage readings resumed after ~${blind_min}min blind; 5h usage now ${util_raw%.*}%. Normal monitoring restored."
  fi
  fail_count=0
  first_fail_epoch=0
  degraded_notified=0
  last_degraded_notice=0
  fail_retry=$FAIL_RETRY_SECS

  util=${util_raw%.*}   # "38.0" -> "38"
  resets=$(jq -r '.five_hour.resets_at // "unknown"' <<<"$resp" 2>/dev/null)
  now=$(date +%s)
  reset_epoch=$(to_epoch "$resets")

  tier=0
  [ "$util" -ge 90 ] && tier=1
  [ "$util" -ge 94 ] && tier=2
  [ "$util" -ge 97 ] && tier=3

  if [ "$tier" -gt 0 ] && [ "$util" -gt "$last_notified_util" ]; then
    case "$tier" in
      1) echo "USAGE-${util}: 5h usage at ${util}% (resets ${resets}). Set a cron wakeup for after reset NOW as insurance; keep working; prefer serial over parallel subagents." ;;
      2) echo "USAGE-${util}: 5h usage at ${util}% (resets ${resets}). ESCALATION (>=94%). If the cron wakeup is not set, set it NOW. Only launch subagent work that is strictly bounded and small." ;;
      3) echo "USAGE-${util}: 5h usage at ${util}% (resets ${resets}). WIND DOWN (>=97%): checkpoint and end your turn. This watchdog stays running and will wake you with USAGE-RESET ~$((RESET_CONFIRM_CUSHION_SECS + RESET_SETTLE_SECS))s after the window resets; a cron wakeup as backup insurance is still wise." ;;
    esac
    last_notified_util=$util
    last_tier=$tier
    # Lock in the boundary on first entry into alert if idle syncing never captured one
    # (e.g. the session started already above 90%).
    [ "$boundary_epoch" -eq 0 ] && [ "$reset_epoch" -gt 0 ] && boundary_epoch=$reset_epoch
    [ "$EXIT_ON_ALERT" = "1" ] && exit 0
  elif [ "$last_tier" -gt 0 ]; then
    # Reset detection. Two independent guards, and both matter:
    #   1. the confirm cushion below, gating when we BELIEVE the roll happened;
    #   2. RESET_SETTLE_SECS, gating when we TELL the session about it.
    rolled=0
    if [ "$boundary_epoch" -gt 0 ]; then
      [ "$now" -ge $((boundary_epoch + RESET_CONFIRM_CUSHION_SECS)) ] \
        && { [ "$util" -lt 50 ] || [ "$reset_epoch" -gt $((boundary_epoch + 300)) ]; } \
        && rolled=1
    elif [ "$util" -lt 50 ]; then
      # No parseable reset time — fall back to a bare utilization drop (can't time-gate
      # the confirmation, which makes the settle delay the only guard on this path).
      rolled=1
    fi
    if [ "$rolled" -eq 1 ]; then
      # Settle before speaking: the API reports the roll before the new window is
      # actually usable. Sleeping here (rather than deferring to the next poll) keeps
      # the delay exact and the state machine linear.
      sleep "$RESET_SETTLE_SECS"
      echo "USAGE-RESET: 5h window reset; usage now ${util}%. Normal operation may resume."
      last_tier=0
      last_notified_util=0
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
  if [ "$last_tier" -gt 0 ]; then
    # ...but while alerting, poll at most every 120s so per-percent ticks are seen
    # (not batched into one multi-percent jump)...
    [ "$interval" -gt 120 ] && interval=120
    # ...and never sleep past the point where the roll becomes believable, so the next
    # wake lands right after the real reset (floor 30s if we're already past it and
    # awaiting a lagging roll).
    if [ "$boundary_epoch" -gt 0 ]; then
      to_reset=$(( boundary_epoch + RESET_CONFIRM_CUSHION_SECS - now ))
      [ "$to_reset" -lt "$interval" ] && interval=$to_reset
      [ "$interval" -lt 30 ] && interval=30
    fi
  fi

  sleep "$interval"
done
