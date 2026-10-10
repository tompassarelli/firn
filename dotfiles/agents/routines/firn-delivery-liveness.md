---
name: firn-delivery-liveness
kind: systemd-timer
schedule: every 30 min
owner: native/nix/delivery-liveness.clause
purpose: Build the committed Firn toplevel without switching so a broken main is found before a rebuild needs it.
relates-to: [dotfiles/agents/skills/firn, native/nix/delivery-liveness.clause]
expires: never
---

~/.local/bin/firn-liveness-floor
