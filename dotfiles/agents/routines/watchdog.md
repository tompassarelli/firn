---
name: watchdog
kind: session-cron
schedule: */5 * * * *
owner: dotfiles/bin/capacity-watchdog
purpose: Every 5 minutes a cheap worker reads the capacity watchdog's 5- and 30-minute windows and tells the lead about any new overload pattern with one recommended action.
relates-to: [dotfiles/bin/capacity-watchdog, modules/capacity-watchdog/default.bnix, dotfiles/agents/hooks/lib/spawn_capacity.py, dotfiles/agents/skills/machine-capacity/SKILL.md]
expires: never
---

Lead: if the previous watchdog worker is still running, skip this tick. Otherwise spawn a `worker-haiku` (the spawn gate exempts this brief) whose brief starts with `[routine:watchdog] Run \`agents routines show watchdog\` and follow it as the watchdog worker.` Relay its line to Tom only when it names a pattern; act on the recommendation as the accountable parent.

Watchdog worker: 1) Run `capacity-watchdog report`; it prints the 5- and 30-minute windows of ~/.local/state/agents/watchdog/samples.jsonl with incidents (~/.local/state/agents/watchdog/incidents.md) and `flags`. 2) Name each flagged pattern: CPU PSI sustained above 40%, a lease owner over its reservation, a client over its measured share, memory under or heading to the floor, an unleased tree or a terminated git maintenance incident, or no samples. Compare with the 30-minute window to call it new or continuing. 3) Return exactly one line: `watchdog: <pattern, owner, numbers> -> <one recommended action>` or `watchdog: quiet (cpu PSI <mean>%, mem <MiB> available)`. Read only; never signal, kill or start anything.
