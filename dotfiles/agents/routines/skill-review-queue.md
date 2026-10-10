---
name: skill-review-queue
kind: systemd-timer
schedule: Mon 09:00 weekly
owner: modules/skill-review-queue/default.bnix
purpose: Open or update the north issue listing skill reviews older than 30 days.
relates-to: [dotfiles/agents/skills/skill-maintenance, north:agent-machinery]
expires: never
placement: laptop
deadline: 2d
---

~/.local/bin/skill-review-queue
Stays on the laptop: nexus has no valid GitHub token (GH_TOKEN is rejected), so gh cannot update the issue there.
