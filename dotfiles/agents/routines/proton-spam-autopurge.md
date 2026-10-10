---
name: proton-spam-autopurge
kind: systemd-timer
schedule: 06:00 daily
owner: native/nix/proton-autopurge.clause
purpose: Daily mail hygiene for Proton (rescue correspondents from spam, purge the rest after a grace period, prune Trash) and Gmail (approved rules), with one status line to Plato.
relates-to: [native/nix/proton-autopurge.clause, ~/code/proton-triage/main]
expires: never
placement: laptop
deadline: 2d
---

~/code/proton-triage/main/daily-run.sh
