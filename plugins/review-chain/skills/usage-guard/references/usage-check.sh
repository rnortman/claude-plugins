#!/usr/bin/env bash
# review-chain usage check — one-shot read of the account's usage windows.
# Same data source as usage-watchdog.sh (see its header for endpoint caveats).
# Exit 0 with a summary on success; exit 1 with a reason if usage is unreadable.
set -u

CONF="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CREDS="$CONF/.credentials.json"
ENDPOINT="https://api.anthropic.com/api/oauth/usage"

if [ ! -f "$CREDS" ]; then
  echo "usage unavailable: no OAuth credentials at $CREDS (API-key session, or logged out)"
  exit 1
fi

token=$(jq -r '.claudeAiOauth.accessToken // empty' "$CREDS" 2>/dev/null)
if [ -z "$token" ]; then
  echo "usage unavailable: no accessToken in $CREDS"
  exit 1
fi

resp=$(curl -sS --max-time 30 \
  -H "Authorization: Bearer $token" \
  -H "anthropic-beta: oauth-2025-04-20" \
  "$ENDPOINT" 2>&1) || { echo "usage unavailable: request failed: $resp"; exit 1; }

jq -e '.five_hour.utilization' <<<"$resp" >/dev/null 2>&1 || {
  echo "usage unavailable: unexpected response shape (token expired? endpoint changed?)"
  exit 1
}

jq -r '
  "5-hour:  \(.five_hour.utilization)%  (resets \(.five_hour.resets_at))",
  "7-day:   \(.seven_day.utilization)%  (resets \(.seven_day.resets_at))",
  # Model-scoped limits (e.g. a Fable-specific weekly cap) live in .limits[] with a
  # non-null .scope; the top-level seven_day_* fields are null now. Print each one.
  (.limits // [] | map(select(.scope != null)) | .[] |
    "\(if .group == "weekly" then "7-day" elif .group == "session" then "5-hour" else .group end) (\(.scope.model.display_name // .scope.surface // .kind)):  \(.percent)%  (resets \(.resets_at))")
' <<<"$resp"
