---
name: tick
kind: session-cron
schedule: 3,13,23,33,43,53 * * * *
owner: dotfiles/agents/skills/workers/SKILL.md
purpose: Every 10 minutes the lead checks unowned work, worker flags and capacity flags and acts only on flagged rows, so a quiet tick spawns nothing and rebuilds nothing.
relates-to: [dotfiles/agents/skills/workers/SKILL.md, dotfiles/agents/skills/workers/references/notes.md, dotfiles/agents/skills/auto-wake/SKILL.md, dotfiles/agents/skills/cloud-workers/SKILL.md, dotfiles/agents/hooks/lead-regrounding.sh, dotfiles/bin/capacity-watchdog, dotfiles/bin/worker-sweep]
expires: never
---

Lead tick (self-scheduled, not Tom). Goal: keep the goal moving; act only on flagged rows. 0) Run `threads unowned`; give each priority:now UNOWNED row a worker (cloud first when code-only) or `threads block <repo#N> <reason>`, capped only by the spawn gate. 1) Run `worker-sweep --session <this session's id>` and `capacity-watchdog report --minutes 5 --minutes 30 | jq -c '{minutes, flags}'`. Act on each flagged worker row (STALLED, OVERTIME, HANDOFF, PARKED) and each WAIT line with the workers skill's named move. A capacity flag absent from the previous status line is new: give it to its accountable parent and tell Tom one line. Read only: never signal, kill or start a process from a flag. 2) When the tick number is a multiple of 3 or steps 0 or 1 changed state, rebuild the DAG from the goal's GitHub issues, main CI, cloud runs and queued landings; attack the critical path's longest wait; staff every unblocked node up to the spawn gate; close issues whose boxes passed. 3) If the prompt ends `Context: <checkpoint path>`, read that checkpoint first and keep it current: goal, tracker, worktrees and resume steps. 4) Write one status line ending with `tick=<n>` and the `threads unowned` summary counts; return one line when no work exists and start no duplicate workers or assurance work. 5) When the goal finishes or Tom stops it, CronDelete this tick.
