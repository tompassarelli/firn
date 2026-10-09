---
name: machine-capacity
description: >-
  Bound sustained multi-core or >1 GiB local work and diagnose agent-caused resource pressure. Skip ordinary edits and small checks.
---

# Machine capacity

- Resolve the helper at `$(dirname "$(agents path machine-capacity)")/scripts/machine-capacity.mjs` and invoke it with Bun.
- Admit sustained multi-core or >1 GiB work through the shared helper, never worker slots or load average.
- Choose the smallest sufficient class: moderate = 2 CPUs/2 GiB; heavy = 6 CPUs/8 GiB; exclusive = all allowed cores/no peer batch; native = 2 CPUs/4 GiB/no CPU quota.
- Use `run --class CLASS --owner OWNER --timeout-seconds N -- COMMAND ARG...` for batch work, including legitimate setup/download time.
- Use `session --class native --owner OWNER -- COMMAND ARG...` for Warcraft clients/private desktops, one scope per client and two per pair.
- Keep native sessions foreground until command exit, Ctrl-C or explicit stop; only native sessions have no default deadline.
- Respect batch session's 30-minute default, batch's one-hour maximum and exclusive's 15-minute maximum.
- Request native-only `--memory-gib 1.5` for measured smaller offline clients.
- Require positive whole-MiB values and retain memory/CPU admission rules.
- Charge that request at 1536 MiB instead of 4096 MiB and apply the same MemoryHigh to that client only.
- Read [leases and limits](references/leases-and-limits.md) for reserve/renew/release commands, admission details and session recovery.
- Respect CPU weights: compositor session 300, native 200, app 100, batch agent 20.
- Keep attended batch within cores minus four and 20% RAM available; defer while protected-slice CPU some avg10 is at least 10%.
- Keep unattended within all cores and an 8 GiB available-memory floor.
- Cap leased memory at 75% RAM in both profiles.
- Use `mode away|present|auto` only for intended presence overrides until reboot.
- Query `mode`/`probe` for active mode/profile.
- Let auto presence switch unattended after 10 minutes without physical keyboard/pointer/pad input and attended within one second of input.
- Exclude automation pads.
- Queue moderate/heavy work in arrival order while declared batch CPUs exceed the core limit or system CPU some avg10 exceeds 30%.
- Let queued exclusive work drain heavy jobs while moderate/update:wisp continue.
- Start after batch leases end and block new batch work until release without blocking native clients.
- Keep every descendant inside its scope and supervise the wrapper through terminal `RELEASED`.
- Never detach work or renewal processes.
- Keep queued wrappers supervised until they start automatically.
- Retry DEFER from probe/reserve/native after a known release or 30 seconds.
- Never busy-poll.
- Treat RUN/RESERVED as permission to continue and RECLAIMED as expired leases/finished helper scopes, never permission to kill peers.
- Retain allowances while wrapper or scope is live, including native sessions.
- Assign exact-scope cleanup to the owner/accountable parent.
- Reserve an agent lease before compute-using workers, renew before expiry and release at settlement.
- Charge 768 MiB without reserving local CPU.
- Give worker local commands their own run scopes; persist reservations only for agent class.
- Respect the spawn gate when leasedBatchCpus reaches aggregateCpuLimit or protectedCpuSomeAvg10 exceeds 20; queue, use the farm or use cloud workers.
- Scale native pairs one at a time and stop adding above protectedCpuSomeAvg10 20 in either profile.
- Use status for holders, remaining seconds and queue order.
- Treat memory PSI as diagnostic and system CPU PSI as admission pacing rather than desktop harm.
- Leave signaling of peers to their owner/accountable parent.
- Never lower correctness requirements because of pressure.
