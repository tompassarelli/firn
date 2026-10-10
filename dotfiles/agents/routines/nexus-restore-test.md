---
name: nexus-restore-test
kind: systemd-timer
schedule: Sun 06:00 weekly, Persistent
owner: modules/nexus-pull/default.bnix
purpose: Decrypt the newest nexus backups in tmpfs with the laptop key, check archive and ledger integrity, and report the result to nexus.
relates-to: [modules/nexus-pull/default.bnix]
expires: never
placement: laptop
deadline: 8d
---

nexus-restore-test.service (user unit on the laptop)
