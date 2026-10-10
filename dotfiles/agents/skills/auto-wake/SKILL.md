---
name: auto-wake
agents: [claude]
description: >-
  Auto-wake mode: when the operator asks for "auto-wake" (or to keep working
  through usage limits, overnight or while away), schedule a recurring
  session tick that resumes the work after a pause and keeps it moving.
grounded: 2026-10-10
written: 2026-10-10
---

# Auto-wake

- Run CronList first. If no session cron carries `[routine:tick]`, schedule the `tick` routine with CronCreate; never create a second one.
- Create recurring jobs only from a `dotfiles/agents/routines/` entry with its pointer prompt (`agents routines pointer tick`), appending ` Context: <checkpoint path>`; keep the goal, tracker/handoff path, worktrees and resume steps in that checkpoint.
- Each tick starts with `threads unowned` and acts only on flagged rows (`worker-sweep` and `capacity-watchdog report`), as the `tick` routine states.
- Tell Tom the terminal must stay open, jobs expire after 7 days and work resumes at the first tick after usage returns.
- Keep the restart checkpoint current.
- Return one line when no work exists and start no duplicate workers or assurance work.
- Delete the tick with CronDelete when the goal finishes or Tom stops it.
