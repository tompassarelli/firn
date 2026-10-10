---
name: heartbeat
kind: session-cron
schedule: 17,47 * * * *
owner: dotfiles/agents/skills/auto-wake/SKILL.md
purpose: Template for the auto-wake heartbeat that resumes a goal after a usage pause and keeps it moving while Tom is away.
relates-to: [dotfiles/agents/skills/auto-wake/SKILL.md, dotfiles/agents/skills/workers/SKILL.md, dotfiles/agents/skills/todo/SKILL.md]
expires: never
---

Auto-wake heartbeat (self-scheduled, not Tom). The pointer prompt ends with `Context: <checkpoint path>`, which names the goal, tracker/handoff and worktrees; read that checkpoint first. 0) Run `threads unowned`; before any other work give each priority:now UNOWNED row a worker (cloud first when code-only) or `threads block <repo#N> <reason>`, capped only by the spawn gate. 1) Run `worker-sweep` and act on every flagged row; read pending messages, resume stopped workers, remove unneeded holds and route main CI failures. 2) Continue unowned work from the checkpoint's resume steps and keep the checkpoint current. 3) Write one status line ending with the `threads unowned` summary counts; return one line when no work exists and start no duplicate workers or assurance work. 4) When the goal finishes or Tom stops it, CronDelete this heartbeat.
