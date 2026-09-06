---
name: machine-capacity-distilled
description: >-
  Bound sustained multi-core or >1 GiB local work and diagnose agent-caused resource pressure. Skip ordinary edits and small checks.
---

# Machine capacity

Use the shared helper, not worker slots or load average, to admit heavy work:

```bash
capacity_skill=$(dirname "$(agents path machine-capacity-distilled)")
capacity="$capacity_skill/scripts/machine-capacity.mjs"
bun "$capacity" run --class heavy --owner "codex:/root/task" \
  --timeout-seconds 900 -- COMMAND ARG...
```

Choose the smallest sufficient class: `moderate` (2 CPUs/2 GiB), `heavy`
(6 CPUs/8 GiB), or `exclusive` (bounded heavy budget with no peer heavy lease).
Set an honest hard runtime bound including legitimate setup and downloads;
the example is not a universal timeout.

The wrapper admits atomically and contains every descendant in one user
cgroup. Do not detach work outside it. One owner retains the terminal
`RELEASED` result and cleans up the exact scope.

`RUN`/`RESERVED` continues; `DEFER` queues heavy work while useful light work
continues. Retry after a known release or at least 30 seconds, never busy-poll.
`RECLAIMED` concerns expired helper-owned leases, not permission to kill peers.
Memory PSI is diagnostic: local cgroup throttling can raise it despite ample
host headroom. Admission uses available memory, lease budgets, and CPU pressure.

Before a parallel worker expected to consume local compute, reserve its
`agent` lease (1 CPU/768 MiB); renew before expiry and release at settlement.
Only `agent` permits persistent reservation. Exact commands and headroom
rules: [nixos-config:capacity leases and limits](references/leases-and-limits.md).

Never kill a peer process. Only its owner or accountable parent may stop the
identified tree. Pressure changes admission, not correctness requirements.
