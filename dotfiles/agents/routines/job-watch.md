---
name: job-watch
kind: systemd-timer
schedule: every 15 min
owner: modules/job-watch/default.bnix
purpose: Push one urgent alert when a registry job with a placement and deadline is overdue (a laptop job past its deadline even while the laptop is off, or online period + 30 min without success), repeat at most daily, and a normal note on recovery.
relates-to: [modules/job-watch/default.bnix, modules/wg-nexus/default.bnix, north:bin/job-watch]
expires: never
placement: nexus
---

job-watch.service (system unit on nexus, runs as tom)
