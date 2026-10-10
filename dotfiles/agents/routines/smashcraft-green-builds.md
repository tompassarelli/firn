---
name: smashcraft-green-builds
kind: systemd-timer
schedule: every 10 min
owner: manual unit in ~/.config/systemd/user (not Nix-declared)
purpose: Fetch Smashcraft origin/main every 10 minutes and install the newest green build under Maps/00-Smashcraft.
relates-to: [north:socrates/skills/warcraft-modding/SKILL.md, ~/code/smashcraft]
expires: never
placement: laptop
---

Fetches Smashcraft origin/main every 10 minutes in a detached runner worktree. It installs the newest green build under Maps/00-Smashcraft.
