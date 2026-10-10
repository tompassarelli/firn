---
name: proton-spam-autopurge
kind: systemd-timer
schedule: 09:30 daily
owner: native/nix/proton-autopurge.clause
purpose: Rescue correspondents from Proton spam, then purge the rest after a grace period.
relates-to: [native/nix/proton-autopurge.clause, ~/proton-triage]
expires: never
---

~/proton-triage/autopurge-run.sh
