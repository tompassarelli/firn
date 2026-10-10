---
name: lane-gc@laptop
kind: systemd-timer
schedule: hourly
owner: modules/lane-gc/default.bnix
purpose: Retire worktrees and branches already on origin/main that are clean, idle and unused in every ~/code container, and list unlanded work so it is continued instead of redone.
relates-to: [dotfiles/bin/lane-gc, dotfiles/agents/hooks/unlanded-work.sh, dotfiles/agents/skills/repo-safety/SKILL.md]
expires: never
placement: laptop
---

~/.local/bin/lane-gc
