---
name: machine-capacity
description: >-
  Bound sustained multi-core or >1 GiB local work and diagnose agent-caused resource pressure. Skip ordinary edits and small checks.
---

# Machine capacity

Use the shared helper, not worker slots or load average, to admit heavy work:

```bash
capacity_skill=$(dirname "$(agents path machine-capacity)")
capacity="$capacity_skill/scripts/machine-capacity.mjs"
bun "$capacity" run --class heavy --owner "codex:/root/task" \
  --timeout-seconds 900 -- COMMAND ARG...
```

Choose the smallest sufficient class. Builds, tests and other batch work use
`moderate` (2 CPUs/2 GiB), `heavy` (6 CPUs/8 GiB), or `exclusive` (every
allowed core, no peer batch lease); they run in the low-weight
`agent-capacity.slice` and only take cycles the desktop and game clients leave
idle. Latency-sensitive Warcraft clients, one scope per client (a pool pair is
two), use `native` (2 CPUs/4 GiB): the high-weight `native.slice`, no CPU quota.
Set an honest hard runtime bound including legitimate setup and downloads;
the example is not a universal timeout.

For offline Warcraft clients with a measured smaller footprint, pass
`--memory-gib 1.5` to `run` or `session` (and `probe` to check admission).
This native-only request charges 1536 MiB instead of the 4096 MiB default and
sets that client's memory high watermark to the same amount; other leases are
unchanged. Requests must be positive and represent whole MiB. The available
memory floor, 75% leased-memory cap, and native CPU admission still apply.
The capacity fixture with 70000 MiB already leased on a 96343 MiB host defers
the default 4 GiB client but admits 1.5 GiB, saving 2.5 GiB per new client.

Interactive desktops and other explicitly retained foreground sessions use
`bun "$capacity" session --class heavy --owner "codex:/root/task" -- COMMAND ARG...`.
They have no wall-clock deadline; command exit, Ctrl-C, or an explicit stop ends
the scope. Keep the wrapper supervised until its `RELEASED` result. Use `run`
with a finite timeout for builds and other bounded jobs. Never replace a deadline
with a very large timeout or detach a renewal process.

CPU weights order contention: `session.slice` (compositor) 300 > `native.slice`
200 > `app.slice` (terminals, browser) 100 > `agent.slice` batch 20. Two
profiles set admission. **attended** (Tom present): batch shares cores minus a
4-core reserve and is refused only while the session or native slice itself
waits for CPU (PSI some avg10 at least 10%); it keeps 20% of RAM available.
**unattended** (Tom away): greedy, every core, no CPU refusal, only an 8 GiB
available-memory floor against swap and OOM. Both cap leased memory at 75% of
RAM. In `auto` mode a presence watcher (`agent-capacity-presence.service`,
started by any helper call) reads keyboard, pointer and pad input, excluding
virtual automation pads; it selects unattended after 10 minutes without input
and attended within a second of input. `bun "$capacity" mode away|present|auto`
overrides it (no argument prints the active profile); the override lasts until
reboot. `probe` reports `profile` and
`mode`. The wrapper admits atomically and contains every descendant in one user
cgroup. Per-job batch CPU allowances are ceilings, not reservations. Exclusive
runs wait for peer batch jobs and block new batch jobs until release; native
clients are never blocked by batch work.
Do not detach work outside the scope. One owner retains the terminal
`RELEASED` result and cleans up the exact scope.

`RUN`/`RESERVED` continues; `DEFER` queues heavy work while useful light work
continues. Retry after a known release or at least 30 seconds, never busy-poll.
`RECLAIMED` concerns expired agent leases or finished helper-owned scopes, not
permission to kill peers. Run allowances remain charged while their wrapper or
scope is live, including throughout an interactive session without a deadline.
System-wide CPU and memory PSI are diagnostic only: batch work at low weight
and per-job quota throttling raise them without hurting the desktop.

Before a parallel worker expected to consume local compute, reserve its
`agent` lease (768 MiB, no local CPU reservation); renew before expiry and
release at settlement. Its local commands still require their own `run` scope.
Only `agent` permits persistent reservation. Exact commands and headroom
rules: [nixos-config:capacity leases and limits](references/leases-and-limits.md).

Never kill a peer process. Only its owner or accountable parent may stop the
identified tree. Pressure changes admission, not correctness requirements.

## Scale native clients by pressure, not by lease count

On 7 Oct 2026 an orchestrator told to "use the idle machine" grew to 20
Warcraft clients, every one inside an admitted native lease. Load reached 76
on 24 cores and protected CPU pressure 75%, which makes native timing checks
fail and the desktop lag. A native lease charges 2 CPUs with no CPU cap and is
admitted on a single pressure reading at its start, while a pool client really
costs about 0.9 of a core plus about 0.4 for its Battle.net browser and 0.3 for
its Wine server; away mode, set while Tom chatted from another device, admits
greedily. Add native pairs one at a time and stop adding while the helper's
`protectedCpuSomeAvg10` is above 20, whether Tom is present or away. "Use the
machine" means use idle cores, never go past them.
