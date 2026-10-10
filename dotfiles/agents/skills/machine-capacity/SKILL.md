---
name: machine-capacity
description: >-
  Bound sustained multi-core or >1 GiB local work and diagnose agent-caused resource pressure. Skip ordinary edits and small checks.
grounded: 2026-10-09
written: 2026-10-09
---

# Machine capacity

- Resolve the helper at `$(dirname "$(agents path machine-capacity)")/scripts/machine-capacity.mjs` and invoke it with Bun.
- Admit sustained multi-core or >1 GiB work through the shared helper, never worker slots or load average.
- Choose the smallest sufficient class: moderate = 2 CPUs/2 GiB; heavy = 6 CPUs/8 GiB; exclusive = all allowed cores/no peer batch; gpu = 1 CPU/2 GiB for headless Chrome/wisp renders (not grim captures), two at a time; native = 2 CPUs/4 GiB/no CPU quota.
- Use critical (all cores minus the attended desktop reserve, 16 GiB, one-hour batch limits, front of the queue, no CPU-capacity or pressure wait) only as the landing-train holder or for a run with an explicit `--critical` release-blocker diagnostic.
- Use `run --class CLASS --owner OWNER --timeout-seconds N -- COMMAND ARG...` for batch work, including legitimate setup/download time.
- Omit `--class` on `run` to size from the usage log: p90 peak cores and memory of the shape's last 20 runs plus 25%, gpu when GPU-busy over a fifth of the run, moderate until three runs exist; the admission line shows `sizing`.
- Use `session --class native --owner OWNER -- COMMAND ARG...` for Warcraft clients/private desktops, one scope per client and two per pair.
- Expect native DEFER_GPU_BUSY while GPU busy averages at least 85% over 5 s with no gpu lease running, and attended DEFER_GPU_CLIENTS while four Warcraft clients run; `status`/`probe` show `gpuBusyPercent`/`gpuClients`/`gpuLeases`.
- Expect gpu DEFER_GPU_SLOTS at two gpu leases and DEFER_NATIVE_WAITING for a minute after a native client was deferred; native clients outrank renders.
- Never start wine, proton, steam-run or a game .exe outside a native session; `native-launch-guard` refuses it.
- Run cargo build, full `bun test` suites, `bun wisp map build` and headless wisp renders (`view`, `headless --render`) through `run`; `heavy-command-guard` refuses them unwrapped.
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
- Respect the spawn gate when committedBatchCpus (each live batch lease at max(reserved, measured cores) plus unleased heavy load) reaches aggregateCpuLimit or protectedCpuSomeAvg10 exceeds 20; queue, use the farm or use cloud workers.
- Scale native pairs one at a time and stop adding above protectedCpuSomeAvg10 20 in either profile.
- Use status for holders, remaining seconds, queue order, each run lease's `measured` cores/memory/GPU beside its reservation, and `unleasedHeavy` (cgroups outside leases, session and native slices averaging over one core for two minutes, sampled by the presence watcher).
- Read `~/.local/state/agents/machine-capacity-usage.jsonl` for each released run's measured CPU seconds, mean/peak cores, peak memory and GPU seconds by owner and command shape.
- Treat memory PSI as diagnostic and system CPU PSI as admission pacing rather than desktop harm.
- Leave signaling of peers to their owner/accountable parent.
- Never lower correctness requirements because of pressure.
