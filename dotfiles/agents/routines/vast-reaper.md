---
name: vast-reaper
kind: systemd-timer
schedule: every 5 min
owner: modules/vast-reaper/default.bnix
purpose: Destroy vast-job instances past their deadline or without a live supervisor so prepaid vast.ai credit is not drained; for the vast-launch-check runner VM warn once at credit <= $5.00 and at <= $2.50 delete FARM_RUNNER on smashcraft and wisp, destroy the VM and remove its SSH key.
relates-to: [dotfiles/bin/vast-reaper, dotfiles/agents/skills/vast-ai/SKILL.md]
expires: never
placement: nexus
deadline: 30min
---

~/.local/bin/vast-reaper
