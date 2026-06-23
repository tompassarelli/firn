# Writing safely under concurrent agents

lodestar threads are backed by the Lodestar claim graph (engine `~/code/fram`;
canonical log `~/.local/state/lodestar/claims.log`). Assume **other agents
may be editing concurrently**:

**Session-start handshake (before coordinating lodestar, mirrors beagle-doctor):**
run `lodestar doctor`. If it reports DOWN/DEGRADED, run
`lodestar up` to start the coordinator on the canonical log.
(Optional heartbeat: `/loop 10m lodestar up` keeps it alive.)

- Creating/editing a thread `.md` is fine — distinct files don't collide. After
  editing, run `lodestar import` to fold edits into the claim
  log (idempotent; safe to run anytime).
- **Do not run `lodestar export` during concurrent work** — it regenerates
  `threads/` from the log and would clobber another agent's un-imported edits.
  (The engine refuses if files diverge, but don't rely on it.)
- **Serialized claim writes go through the coordinator** via `lodestar tell <id>
  <pred> <value>` / `untell <id> <pred> <value>` — these route to the running
  daemon (serialized, rule-checked, retries on conflict). Do NOT use `lodestar
  set`, which appends the log directly and races. For creating whole new threads,
  `lodestar capture "<title>"` (claim-first) or file-edit + `import` is fine
  (distinct files don't collide); for field changes on existing threads under
  concurrency, prefer `tell`.
- Reads are instant off the warm daemon (`lodestar serve`): ready / blocked /
  leverage / validate in ~1ms.
