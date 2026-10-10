---
name: nexus-lynis
kind: systemd-timer
schedule: Sun 05:30 weekly
owner: modules/nexus-checks/default.bnix
purpose: Weekly lynis audit; alert only when the hardening index drops or a new warning appears.
relates-to: [modules/nexus-checks/default.bnix]
expires: never
placement: nexus
deadline: 8d
---

nexus-lynis.service (system unit on nexus)
