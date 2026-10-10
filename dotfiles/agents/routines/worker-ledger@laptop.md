---
name: worker-ledger@laptop
kind: systemd-timer
schedule: every 15 min
owner: modules/worker-ledger/default.bnix
purpose: Record finished Claude and Codex workers as runs in threads and fill the landings of runs still waiting to land, every 15 minutes.
relates-to: [dotfiles/bin/worker-ledger, dotfiles/bin/threads]
expires: never
placement: laptop
---

Records each finished Claude or Codex worker as a run in its thread every 15 minutes. It then fills in the landing of any run that is still waiting to land.
