---
name: vast-reaper
kind: systemd-timer
schedule: every 5 min
owner: modules/vast-reaper/default.bnix
purpose: Destroy vast-job instances past their deadline or without a live supervisor so prepaid vast.ai credit is not drained.
relates-to: [dotfiles/bin/vast-reaper, dotfiles/agents/skills/vast-ai/SKILL.md]
expires: never
---

~/.local/bin/vast-reaper
