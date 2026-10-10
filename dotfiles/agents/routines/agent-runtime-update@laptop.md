---
name: agent-runtime-update@laptop
kind: systemd-timer
schedule: 02:00 and 13:00 daily
owner: modules/agent-runtime-update/default.bnix
purpose: Update the Claude Code and Codex runtimes twice a day.
relates-to: [modules/agent-runtime-update/default.bnix]
expires: never
placement: laptop
deadline: 2d
---

~/.local/share/north/bin/agent-runtime-update
