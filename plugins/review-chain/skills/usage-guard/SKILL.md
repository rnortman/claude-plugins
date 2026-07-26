---
name: usage-guard
description: Arm a background watchdog on the account's 5-hour usage window
disable-model-invocation: true
---

Arm a usage watchdog for this session. The watchdog is a long-running script that polls the account's 5-hour usage window and, once utilization reaches 90%, emits one alarm line for every integer-percent increase; run under the Monitor tool, each line wakes this session — even when fully idle — so you can watch usage tick up and react. It polls adaptively ((99 − utilization) minutes, clamped to 60s–480s) and costs nothing meaningful.

## Arming

1. Resolve the absolute path of `references/usage-watchdog.sh` from this skill's directory.
2. Take a baseline reading first: `bash <skill-dir>/references/usage-check.sh`. If it fails (no OAuth credentials — e.g. an API-key session), report that to the user and stop; the watchdog cannot work here.
3. Arm via the Monitor tool:
   - `command`: `bash <abs-path>/usage-watchdog.sh`
   - `description`: `5h usage watchdog`
   - `persistent`: `true`
4. Confirm to the user: armed, current utilization, and the window's reset time.

If the Monitor tool is not available in this session, fall back to `Bash` with `run_in_background: true` and env `WATCHDOG_EXIT_ON_ALERT=1` on the command. In that mode the watchdog exits at the first alarm (background shells only notify on exit) — after handling each alarm, re-arm it the same way.

## Responding to watchdog events

Each event arrives as a task notification whose line tells you most of what to do. Alarm lines are `USAGE-<pct>` (e.g. `USAGE-92`), one per integer-percent increase from 90% up, so you see usage ticking toward the wall; the instruction in each line is tier-based. Full doctrine by tier:

- **90–93% — mild.** Schedule the post-reset wakeup NOW as insurance (one-shot cron/scheduled wakeup for 1 minute after the `resets` time in the message), then keep working normally, but prefer running subagents serially rather than in parallel from here on.
- **94–96% — escalation.** If the wakeup somehow isn't scheduled yet, that is now the first priority. Only launch further subagent work that is strictly bounded and small; checkpoint anything in flight.
- **97%+ — stop.** Commit/checkpoint current state, confirm the wakeup is scheduled, tell the user you're pausing for the usage window, and end your turn. Do not start anything new. Under the Monitor tool the watchdog keeps running past this point — it will wake you with `USAGE-RESET` itself once the window actually rolls over, so the scheduled wakeup is only backup insurance.
- **`USAGE-RESET`** — the 5-hour window has rolled over into a fresh one (the watchdog waited until ~45s past the nominal reset time and confirmed the drop with the API before sending this). Normal operation may resume; cancel a now-pointless wakeup if one is pending. The watchdog is still running and now silently guards the new window.
- **`WATCHDOG-DEGRADED`** — the watchdog has been unable to read usage for a sustained stretch (API outage, expired token, network). It does NOT give up: it keeps retrying indefinitely and rate-limits these notices (at most one per 30 minutes). While degraded, monitoring is blind — do not assume headroom. No action needed beyond caution; if you no longer need monitoring, kill the monitor (see below).
- **`WATCHDOG-RECOVERED`** — readings resumed after a degraded stretch; the message includes current utilization. Normal monitoring is restored.
- **`WATCHDOG-DISARMED`** — fired only at startup when no OAuth credentials exist (API-key session, or logged out); the watchdog exits. Tell the user monitoring is unavailable.
- **Monitor stream ended** with none of the above: the watchdog died unexpectedly — monitoring is DOWN; re-invoke this skill to re-arm if still needed.

Percentages can be skipped: a single burst can jump from 89% to 96%, in which case one alarm fires at 96%. Treat any alarm as also implying everything the lower tiers ask for.

On waking after the scheduled post-reset wakeup: under the Monitor tool the watchdog is already running and guarding the new window, so no re-arm is needed. Only re-invoke this skill to re-arm if the watchdog has stopped (`WATCHDOG-DISARMED`, Monitor stream ended, or the `WATCHDOG_EXIT_ON_ALERT=1` background fallback, which does exit at each alarm).

## Killing the watchdog

The watchdog never gives up on its own — you own the kill switch. **Kill the monitor when your task is done or you are blocked waiting on the user.** Every watchdog line wakes this session, and waking an idle session is particularly expensive (prompt-cache miss on the whole context) — an unattended watchdog burning wake-ups on a session with nothing to do wastes exactly the tokens it exists to protect. Re-arm by re-invoking this skill when active work resumes.

## Manual check

`bash <skill-dir>/references/usage-check.sh` prints the current 5-hour and 7-day utilization and reset times (in local time, ready to schedule against) any time — plus any model-scoped weekly caps the API reports (e.g. a Fable-specific weekly limit) — useful before deciding to launch a large parallel fan-out. Anyone (user or agent) may run it; only arming the watchdog is gated behind this skill.
