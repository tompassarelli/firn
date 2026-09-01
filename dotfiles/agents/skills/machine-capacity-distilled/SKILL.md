---
name: machine-capacity-distilled
description: >-
  Admit and contain local CPU- or memory-intensive agent work without
  oversubscribing the shared machine. Use before starting a sustained
  multi-core or more-than-1-GiB command, browser/compiler/full-test canary, or a
  parallel worker expected to run such work, and when diagnosing machine
  pressure caused by agent-owned processes. Do not use for ordinary edits,
  bounded searches, or known-subsecond focused checks.
---

# Machine capacity

Preserve interactive headroom through one cheap shared decision. Do not infer
capacity from idle worker slots, load average alone, or a manual process census.

Resolve the active helper once:

```bash
capacity_skill=$(dirname "$(agents path machine-capacity-distilled)")
capacity="$capacity_skill/scripts/machine-capacity.mjs"
```

## Admission

- `agent` reserves 1 CPU and 768 MiB for one parallel worker expected to use
  local compute.
- `moderate` reserves 2 CPUs and 2 GiB.
- `heavy` reserves 6 CPUs and 8 GiB.
- `exclusive` reserves the machine's bounded heavy-work budget and admits no
  peer heavy lease.

Wrap every sustained compiler, browser, Wasm, full-test, profiling, or similar
command. Give it the shortest honest runtime bound:

```bash
bun "$capacity" run --class heavy --owner "codex:/root/task" \
  --timeout-seconds 900 -- COMMAND ARG...
```

The wrapper atomically admits the work, caps it in one transient user cgroup,
and keeps the scope alive until every descendant exits. Do not daemonize,
background, or detach servers and browsers outside that command. The scope
reaps the exact process tree on timeout or cancellation.

Before admitting a parallel worker expected to use local compute, reserve an
`agent` lease. Persistent `reserve` is mechanically limited to `agent`; use a
bounded `run` scope for `moderate`, `heavy`, or `exclusive`. Release the lease
when that child settles; renew it only before its declared bound expires:

```bash
bun "$capacity" reserve --class agent --owner "codex:/root/task" --timeout-seconds 1800
bun "$capacity" renew --lease LEASE --owner "codex:/root/task" --timeout-seconds 1800
bun "$capacity" release --lease LEASE --owner "codex:/root/task"
```

The helper returns one immediate machine-readable decision. `RUN`/`RESERVED`
continues. `DEFER` means queue the heavy node and continue only light useful
work; retry after a known lease release or after at least 30 seconds, never by
busy polling. `RECLAIMED` reports expired helper-owned leases removed during
the decision.

Admission reserves 25% of CPUs, at least 20% and 4 GiB of available memory,
and refuses new heavy work while Linux CPU PSI reports 20% or more stalled time
over 10 seconds or any full-memory stall. Resource pressure may delay optional
breadth; it never weakens the required correctness check.

## Ownership and recovery

One actor owns each admitted scope and its lease through terminal cleanup.
Settlement requires retaining the helper's machine-readable `RELEASED` result;
prose or a terminal report is not release evidence. If a settled child did not
return it, the accountable parent must release the exact known lease and retain
that result.

Never kill or reclaim a peer process. An expired lease is helper-owned state and
may be reclaimed automatically; its matching cgroup has the same hard runtime
bound. If unleased work causes pressure, defer new heavy work and identify the
exact owner through bounded native process metadata. Only that owner or its
accountable parent may stop the exact process tree.

Do not add a daemon, dashboard, recurring census, temperature poller, or generic
observability lane. This protocol is paid only at heavy-work admission and
terminal release.
