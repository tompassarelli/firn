---
name: checkout-sync
kind: systemd-timer
schedule: every 15 min
owner: modules/checkout-sync/default.bnix
purpose: Fast-forward each clean ~/code/<project>/main to origin/main on nexus, where nothing lands locally, so agents and tools read current code.
relates-to: [modules/checkout-sync/default.bnix]
expires: never
placement: nexus
deadline: 2h
---

checkout-sync.service (user unit on nexus)
