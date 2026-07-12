---
name: usage-guard
description: Arm a background watchdog on the account's 5-hour usage window
disable-model-invocation: true
---

Arm a usage watchdog for this session. The watchdog is a long-running script that polls the account's 5-hour usage window and emits one alarm line per threshold crossing; run under the Monitor tool, each line wakes this session — even when fully idle — so you can react. It polls adaptively ((99 − utilization) minutes, clamped to 60s–480s) and costs nothing meaningful.

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

Each event arrives as a task notification whose line tells you most of what to do. Full doctrine:

- **`USAGE-90`** — mild. Schedule the post-reset wakeup NOW as insurance (one-shot cron/scheduled wakeup for 1 minute after the `resets` time in the message), then keep working normally, but prefer running subagents serially rather than in parallel from here on.
- **`USAGE-95`** — escalation. If the wakeup somehow isn't scheduled yet, that is now the first priority. Only launch further subagent work that is strictly bounded and small; checkpoint anything in flight.
- **`USAGE-98`** — stop. Commit/checkpoint current state, confirm the wakeup is scheduled, tell the user you're pausing for the usage window, and end your turn. Do not start anything new.
- **`USAGE-RESET`** — the window reset while the watchdog was still running (usage fell back below 50%). Normal operation may resume; cancel a now-pointless wakeup if one is pending.
- **`WATCHDOG-DISARMED`** — the watchdog could not read usage (expired token, endpoint change, network) and has shut itself down. Monitoring is DOWN: do not assume headroom. Tell the user; optionally re-arm to retry.
- **Monitor stream ended** with none of the above: the watchdog died unexpectedly — treat as DISARMED.

Tiers can be skipped: a single burst can jump from 89% to 96%, in which case only the highest crossed tier fires. Treat any first alarm as also implying everything the lower tiers ask for.

On waking after the scheduled post-reset wakeup: if the session continues working, re-invoke this skill to re-arm the watchdog for the new window.

## Manual check

`bash <skill-dir>/references/usage-check.sh` prints the current 5-hour and 7-day utilization and reset times any time — useful before deciding to launch a large parallel fan-out. Anyone (user or agent) may run it; only arming the watchdog is gated behind this skill.
