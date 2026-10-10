---
name: skill-review-queue
kind: systemd-timer
schedule: Mon 09:00 weekly
owner: modules/skill-review-queue/default.bnix
purpose: Open or update the north issue listing skill reviews older than 30 days.
relates-to: [dotfiles/agents/skills/skill-maintenance, north:agent-machinery]
expires: never
placement: nexus
deadline: 2d
---

~/.local/bin/skill-review-queue
