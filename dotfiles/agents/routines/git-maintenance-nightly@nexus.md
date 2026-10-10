---
name: git-maintenance-nightly@nexus
kind: systemd-timer
schedule: daily 03:17
owner: modules/capacity-watchdog/default.bnix
purpose: Run git maintenance for each ~/code/*/main one repo at a time inside a moderate capacity lease, since automatic detached maintenance is off after unleased repacks took 16 cores and 34 GB.
relates-to: [dotfiles/bin/git-maintenance-nightly, native/nix/git.clause, dotfiles/bin/capacity-watchdog]
expires: never
placement: nexus
---

~/.local/bin/git-maintenance-nightly
