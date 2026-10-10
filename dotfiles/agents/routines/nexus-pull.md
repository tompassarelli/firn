---
name: nexus-pull
kind: systemd-timer
schedule: 05:30 daily, Persistent, and once after boot
owner: modules/nexus-pull/default.bnix
purpose: Copy nexus's age-encrypted backups (*.age only) over WireGuard into ~/backups/nexus and keep 5 weeks; tells nexus when it last pulled.
relates-to: [modules/nexus-pull/default.bnix]
expires: never
placement: laptop
deadline: 7d
---

nexus-pull.service (user unit on the laptop)
