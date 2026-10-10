---
name: lane-sweep
kind: systemd-timer
schedule: 04:30 daily
owner: native/nix/lane-sweep.clause
purpose: Archive and remove worktree lanes idle for a day.
relates-to: [dotfiles/bin/lane-sweep, dotfiles/agents/skills/repo-safety]
expires: never
---

~/.local/bin/lane-sweep
