---
name: usage-wall
description: Ride the 5-hour usage window into the wall — schedule a post-reset wakeup, then resume stalled subagents. No watchdog, no throttling.
disable-model-invocation: true
---

The account's usage limit resets on a rolling 5-hour window. This skill's policy: work at full speed until that window runs out, let the wall stop the session, and pick up exactly where it stopped once the window resets. Nothing is monitored and nothing is slowed down — the only machinery is a one-shot cron wakeup scheduled for two minutes past the reset time, rescheduled after each reset.

Running into the wall is cheap because it stalls in-flight subagents rather than killing them: `SendMessage(<agent>, "Continue")` resumes one from its transcript with its full context and work in progress intact. Nothing is lost, so there is nothing to spend budget defending against.

## Arming

1. Read the current window: `bash <skill-dir>/../usage-guard/references/usage-check.sh`. That script — shared with the `usage-guard` skill in this same plugin — prints 5-hour and 7-day utilization with reset times in local time. If it fails (no OAuth credentials — an API-key session), report that and stop; there is no reset time to schedule against.
2. Compute the cron fields for reset + 2 minutes:
   ```bash
   bash <skill-dir>/../usage-guard/references/usage-check.sh \
     | sed -n 's/^5-hour:.*resets \(.*\))$/\1/p' \
     | xargs -I{} date -d "{} + 2 minutes" '+%M %H %d %m'
   ```
   Output is the first four cron fields in local time, e.g. `02 22 26 07`.
3. Schedule it with `CronCreate`: `cron` = those four fields plus ` *`, `recurring: false`, and the wakeup prompt below verbatim.
4. Tell the user: current utilization, the reset time, and that the session will run into the wall rather than slow down.
5. Keep working. Do not throttle, do not serialize subagents, do not checkpoint early on account of usage, do not check usage again before the wakeup — the whole premise here is that the wall is recoverable, so spending budget to avoid it is wasted budget.

The wakeup prompt must be self-contained; the wakeup may land in a context that has lost the details:

> Usage window reset wakeup. Do these in order: (1) For every subagent that was in flight when the window ran out, `SendMessage(<name-or-agentId>, "Continue")` — one per stalled agent, that word alone, nothing else. Do not respawn them; respawning discards their work. (2) Re-run `bash <skill-dir>/../usage-guard/references/usage-check.sh`, confirm the window actually rolled over, and schedule the next post-reset wakeup the same way with this same prompt. (3) Resume the main task where it stopped.

## Hitting the wall

Requests start failing and the turn ends with an error. That is the expected outcome, not a malfunction. Anything in flight stops mid-work and waits.

Before the wakeup fires there is nothing to do — the session is out of budget, so any attempt to tidy up just fails too.

## On waking

1. **Confirm the reset.** Re-run the check. If 5-hour utilization is still near 100%, the clock was off — schedule another one-shot a few minutes out and stop there.
2. **Resume the stalled agents.** One `SendMessage(<agent>, "Continue")` per agent that was in flight. Refer to them by name where they have one; use the raw `agentId` from the spawn result otherwise. Send nothing beyond `Continue` — the agent reads its own transcript and knows what it was doing, and a re-brief only competes with what it already knows.
3. **Reschedule.** The new window has a new reset time; arm the next one-shot wakeup from step 2 of Arming. This repeats for as long as the work does.
4. **Continue the main task.**
