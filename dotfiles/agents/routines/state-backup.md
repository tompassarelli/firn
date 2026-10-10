---
name: state-backup
kind: systemd-timer
schedule: 03:00 daily, Persistent
owner: modules/nexus-backup/default.bnix
purpose: Dump the ledger and archive nexus state (handoffs, transcripts, job state) through zstd and age to the laptop and offline recovery keys; nexus can't read its own backups.
relates-to: [modules/nexus-backup/default.bnix]
expires: never
placement: nexus
deadline: 26h
---

state-backup.service (system unit on nexus)
