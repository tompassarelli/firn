---
name: lane-gc@nexus
kind: systemd-timer
schedule: hourly
owner: modules/lane-gc/default.bnix
purpose: Retire worktrees and branches already on origin/main that are clean, idle and unused in every ~/code container, and list unlanded work so it is continued instead of redone.
relates-to: [north:bin/lane-gc, north:socrates/hooks/unlanded-work.sh, north:socrates/skills/repo-safety/SKILL.md]
expires: never
placement: nexus
---

~/.local/share/north/bin/lane-gc
