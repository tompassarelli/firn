---
name: nexus-heartbeat
kind: systemd-timer
schedule: every 30 min
owner: modules/nexus-checks/default.bnix
purpose: Write NEXUS_HEARTBEAT on firn for the outside GitHub Actions watchdog (nexus-watch.yml).
relates-to: [modules/nexus-checks/default.bnix]
expires: never
placement: nexus
deadline: 2h
---

nexus-heartbeat.service (system unit on nexus)
