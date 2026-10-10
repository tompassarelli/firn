---
name: auto-wake
agents: [claude]
description: >-
  Auto-wake mode: when the operator asks for "auto-wake" (or to keep working
  through usage limits, overnight or while away), schedule a recurring
  session heartbeat that resumes the work after a pause and keeps it moving.
grounded: 2026-10-10
written: 2026-10-10
---

# Auto-wake

- Schedule one session heartbeat every 30 minutes on off-minutes through CronCreate after checking CronList.
- Create recurring jobs only from a `dotfiles/agents/routines/` entry with its pointer prompt (`agents routines pointer heartbeat`), appending ` Context: <checkpoint path>`; keep the goal, tracker/handoff path, worktrees and resume steps in that checkpoint.
- Start each heartbeat with `threads unowned`: before any other work, give each priority:now UNOWNED row a worker (cloud first when code-only) or `threads block <repo#N> <reason>`, capped only by the spawn gate, and put its summary counts in the status line.
- Run `worker-sweep` and act on every flagged row, read pending messages, resume stopped workers, remove unneeded holds, route main CI failures, checkpoint and continue unowned work at each heartbeat.
- Tell Tom the terminal must stay open, jobs expire after 7 days and work resumes at the first heartbeat after usage returns.
- Keep the restart checkpoint current.
- Return one line when no work exists and start no duplicate workers or assurance work.
- Delete the heartbeat with CronDelete when the goal finishes or Tom stops it.
