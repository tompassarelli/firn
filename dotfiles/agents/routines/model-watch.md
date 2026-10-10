---
name: model-watch
kind: systemd-timer
schedule: 02:10 and 13:10 daily
owner: modules/model-watch/default.bnix
purpose: Read public model release sources twice daily, persist snapshots and print newly observed model events to the journal.
relates-to: [dotfiles/bin/model-watch, dotfiles/agents/lib/usage_claude.py]
expires: never
placement: laptop
deadline: 1d
---

~/.local/bin/model-watch

Stays on the laptop: its usage refresh needs a Claude sign-in, which nexus does not have yet.
