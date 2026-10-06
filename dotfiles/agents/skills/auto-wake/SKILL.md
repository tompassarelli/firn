---
name: auto-wake
description: >-
  Auto-wake mode: when the operator asks for "auto-wake" (or to keep working
  through usage limits, overnight or while away), schedule a recurring
  session heartbeat that resumes the work after a pause and keeps it moving.
---

# Auto-wake mode

The operator wants unattended work to survive usage-limit pauses and stalls:
when the session can run again, it should pick the work back up without them.

## Set it up

1. Use the session scheduler (Claude Code: `CronCreate`) for a recurring
   heartbeat every 30 minutes, on off-minutes (for example `7,37 * * * *`).
   One heartbeat per session: check `CronList` first and replace an existing
   one rather than stacking a second.
2. Write the heartbeat prompt as a self-contained resume procedure for the
   current goal. Name the goal, the handoff or tracker file to read, the
   work's lanes, and these steps:
   - read pending notifications and agent messages;
   - check each live worker, and restart or re-brief one that stopped
     mid-task;
   - undo temporary holds that nothing still needs, such as frozen jobs or
     quiet windows;
   - check CI on the main branch and route new failures to their owner;
   - write a short checkpoint (closed, live, blocked) to the handoff;
   - continue the next unowned work.
3. Tell the operator once how it behaves:
   - it lives only as long as this session (keep the terminal open);
   - recurring jobs expire after 7 days;
   - after a usage pause it resumes at the first heartbeat once usage is back.

## While it runs

- A heartbeat that finds nothing to do says so in one line and does no
  assurance work. It never starts duplicate workers for work already owned.
- Keep the checkpoint current enough that a fresh session could take over
  from it alone.
- Stop the heartbeat (`CronDelete`) when the goal is done or the operator
  says stop.
