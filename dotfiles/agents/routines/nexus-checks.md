---
name: nexus-checks
kind: systemd-timer
schedule: every 15 min
owner: modules/nexus-checks/default.bnix
purpose: Standing checks on nexus (unexpected logins, failed units, update age, disk, backup freshness); push an ntfy alert once per failure and a recovery note.
relates-to: [modules/nexus-checks/default.bnix]
expires: never
placement: nexus
deadline: 1h
---

nexus-checks.service (system unit on nexus)
