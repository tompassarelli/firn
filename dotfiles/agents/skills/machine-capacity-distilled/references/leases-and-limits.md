# Capacity leases and limits

## Why admission is shared

Idle agent slots do not measure local CPU or memory capacity. A shared atomic
lease prevents several individually reasonable commands from starting together
and exhausting interactive headroom. Cgroups bound descendants as well as the
original command; an estimated duration does not provide that containment.

## Worker leases

Resolve the helper as in the distilled guide. Reserve before admitting a
compute-using child, renew before its bound expires, and retain the release:

```bash
bun "$capacity" reserve --class agent --owner "codex:/root/task" --timeout-seconds 1800
bun "$capacity" renew --lease LEASE --owner "codex:/root/task" --timeout-seconds 1800
bun "$capacity" release --lease LEASE --owner "codex:/root/task"
```

These values illustrate a bounded run, not a deadline prediction. Persistent
reservation is limited to `agent`; all larger classes use `run` or `session`.
A settled child missing release evidence leaves the parent responsible for
releasing the exact known lease. A prose report is not a release receipt.

## Headroom and pressure

The helper reserves 25% of CPUs and memory headroom of at least 20% and 4 GiB.
It defers work at CPU PSI of 20% or more over ten seconds, insufficient
available memory, or memory lease budgets above 75% of host capacity.
Every local job joins `agent-capacity.slice`, whose aggregate CPU quota is 75%
of host CPUs. The sum of per-job CPU ceilings may exceed that quota: sleeping
or serial jobs do not consume their ceilings continuously. Agent reservations
retain their 768 MiB memory budget without charging remote inference as local
CPU work. Admission reports CPU pressure separately from CPU ceilings and the
aggregate limit; a reserved ceiling is not a utilization measurement.

Exclusive work requires no other local run lease and prevents new local runs
until release; agent memory reservations may coexist. A run lease outside the
aggregate limit defers new local jobs until its owner finishes. Activation
must therefore wait for old helper invocations to drain; never move or kill
peer jobs to activate this policy.
Full-memory PSI remains diagnostic telemetry: cgroup-local throttling can
raise it without exhausting host headroom, so it does not independently veto
admission. Per-job CPU and memory bounds still apply. `run` also requires a
finite runtime bound; `session` deliberately has no wall-clock deadline.
The helper implementation owns these thresholds; inspect it
when changing admission behavior rather than adding a parallel calculator.

Agent leases expire at their reservation deadline. Run leases record the exact
wrapper PID and Linux process start time, and remain charged while that wrapper
or its uniquely named scope is live. This covers startup, normal execution,
and cleanup without a renewal process or an expiring allowance for a live scope.
Only the foreground wrapper releases a run lease, after stopping the scope;
a failed stop retains the allowance. A dead wrapper's allowance is reclaimable
only after its scope is inactive. Unknown systemd state retains the allowance.
Unleased pressure is different: defer heavy work, identify
the exact process owner with bounded native metadata, and leave signaling to
that owner or accountable parent.

## Interactive session lifetime

Use `bun "$capacity" session --class heavy --owner OWNER -- COMMAND ARG...`
for a foreground interactive session intended to remain until explicitly
stopped. It sets systemd's runtime limit to infinity but retains the same atomic
admission, aggregate CPU quota, memory ceiling, and descendant containment.
Command exit and SIGINT/SIGTERM/SIGHUP to the wrapper stop the exact scope and
produce `RELEASED`. Never detach its command tree. A forcibly killed wrapper
cannot perform cleanup; its still-live scope remains accounted until its owner
stops that exact scope. No automatic restart or timer extension is implied.

Private desktops use this mode by default. `--seconds` selects a finite desktop
deadline instead. An enclosing finite scope still imposes its deadline, so
launch a retained desktop directly or inside a `session` scope. Existing
already-running launchers keep their captured timers; changing the installed
source does not migrate them.

## Alternatives and limits

Manual process censuses are neither atomic admission nor process ownership.
A daemon, dashboard, temperature poller, or recurring census adds no needed
guarantee to this protocol. Pay for admission at start and release at settlement.
Do not mistake a large timeout for evidence that useful progress continues.
