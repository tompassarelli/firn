# Writing safely under concurrent agents

tern threads are backed by the Tern claim graph (engine `~/code/fram`;
canonical log `~/.local/state/tern/claims.log`). Assume **other agents
may be editing concurrently**:

**Session-start handshake (before coordinating tern, mirrors beagle-doctor):**
run `tern doctor`. If it reports DOWN/DEGRADED, run
`tern up` to start the coordinator on the canonical log.
(Optional heartbeat: `/loop 10m tern up` keeps it alive.)

- Creating/editing a thread `.md` is fine — distinct files don't collide. After
  editing, run `tern import` to fold edits into the claim
  log (idempotent; safe to run anytime).
- **Do not run `tern export` during concurrent work** — it regenerates
  `threads/` from the log and would clobber another agent's un-imported edits.
  (The engine refuses if files diverge, but don't rely on it.)
- **Serialized claim writes go through the coordinator** via `tern tell <id>
  <pred> <value>` / `untell <id> <pred> <value>` — these route to the running
  daemon (serialized, rule-checked, retries on conflict). Do NOT use `tern
  set`, which appends the log directly and races. For creating whole new threads,
  `tern capture "<title>"` (claim-first) or file-edit + `import` is fine
  (distinct files don't collide); for field changes on existing threads under
  concurrency, prefer `tell`.
- Reads are instant off the warm daemon (`tern serve`): ready / blocked /
  leverage / validate in ~1ms.
