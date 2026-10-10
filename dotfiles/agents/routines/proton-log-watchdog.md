---
name: proton-log-watchdog
kind: systemd-timer
schedule: every 10 min
owner: modules/proton-log-watchdog/default.bnix
purpose: Strip PROTON_LOG from Wisp clone launch.sh and truncate clone steam-*.log over 1 GiB, after debug logs filled the disk and hung the desktop.
relates-to: [modules/proton-log-watchdog/default.bnix, north:socrates/skills/warcraft-modding/SKILL.md]
expires: never
placement: laptop
---

~/.local/bin/proton-log-watchdog
