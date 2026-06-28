---
description: One-shot timer — re-fire a prompt to yourself after N minutes
argument-hint: "<minutes> <prompt to run on wake>"
---

# /wake

Schedule a single deferred prompt. Parse `$ARGUMENTS`:

- **First token** = `N`, the delay in **minutes**.
- **Rest** = the PROMPT to execute when you wake.

Then call `ScheduleWakeup`:

- `delaySeconds` = `N * 60` (runtime clamps to 60–3600s, i.e. 1–60 min — if `N`
  is outside that, say so and use the clamped value).
- `prompt` = the rest of the args, verbatim — the work to do on wake.
- `reason` = one short line naming the deferred task.

This is a **one-shot timer, NOT a loop**: when you wake, execute the prompt once
and STOP. Do not call `ScheduleWakeup` again, do not reschedule.

After scheduling, confirm in one line — `⏰ waking in N min → <prompt>` — then yield.

If `N` isn't a number or the prompt is empty, don't schedule; ask for `<minutes> <prompt>`.
