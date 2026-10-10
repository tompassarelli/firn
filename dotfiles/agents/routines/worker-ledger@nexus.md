---
name: worker-ledger@nexus
kind: systemd-timer
schedule: every 15 min
owner: modules/worker-ledger/default.bnix
purpose: Record finished Claude and Codex workers as runs in threads and fill the landings of runs still waiting to land, every 15 minutes.
relates-to: [north:bin/worker-ledger, north:bin/threads]
expires: never
placement: nexus
---

Records each finished Claude or Codex worker as a run in its thread every 15 minutes. It then fills in the landing of any run that is still waiting to land.
