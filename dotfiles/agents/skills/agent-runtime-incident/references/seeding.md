# Seeding and deduplication

## Incident invariant

Treat delivery and reliability as independent lifecycles. An unexplained
admission, startup, death, liveness, control, or reporting anomaly seeds or
joins exactly one durable `IncidentSeed`. Delivery may continue through
quarantine, replacement, or an already-authorized fallback, but delivery
completion never closes the incident.

## Evidence and signature contract

Before a retry or replacement changes the evidence, preserve intended
operation, emitted recipient/tool and argument shape, exact error or terminal
signal, runtime/provider mode, actor/run identity, time, correction history,
and the affected seam. Store bounded evidence or exact references; exclude
credentials and unrelated transcript content.

Create or join one `IncidentSeed` in the current authorized durable
continuity record with:

- `signature`, `generation`, `state`, `lifecycle_class`, `cause_class`, and
  stable affected seam or surface scope;
- intended and emitted operations, normalized argument shape, runtime mode,
  error class, first/last observation, count, and preservation evidence;
- containment, delivery state, hypotheses, one reproduction, and upstream owner;
- repair, regression, activation, primary-canary, and restoration-debt evidence.

Derive the stable signature from the canonical tuple
`(lifecycle class, stable affected actor or sender role, intended operation or
report boundary, emitted recipient/tool or payload surface, normalized
argument or payload signature, runtime/provider mode, error class, stable
affected seam/surface scope)`. Exclude timestamps, run-specific actor and
opaque IDs, and secret or volatile values. Normalize scope to the smallest
stable, non-run-specific seam or surface. If one observation spans multiple
scopes, split it deterministically and create or join one seed per scope;
never deduplicate across scopes.

A complete tuple match updates last observation, count, and evidence instead
of creating another seed, including a retry with a new run identity. A changed
tuple is a new signature until evidence proves otherwise. For reporting or
control payload failures, retain a normalized envelope/error signature rather
than the opaque payload itself.

## Why the signature excludes run identity

A replacement run may reproduce the same cause. Including its opaque ID would
fragment one incident into many; dropping the affected semantic scope would
merge unrelated failures. The normalized tuple balances those risks. Hypotheses
remain hypotheses until the reproduction supports a cause.
