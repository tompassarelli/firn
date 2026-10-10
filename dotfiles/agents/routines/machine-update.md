---
name: machine-update
kind: systemd-timer
schedule: 02:00 daily
owner: modules/machine-update/default.bnix
purpose: Nightly machine software update.
relates-to: [modules/machine-update/default.bnix]
expires: never
placement: laptop
deadline: 3d
---

~/.local/share/firn/bin/machine-update
