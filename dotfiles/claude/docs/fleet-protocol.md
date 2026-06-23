# Fleet protocol — driving agents via lodestar/fram

When work means multiple agents, do NOT default to the host's generic `Agent` /
`Workflow` / ultracode spawning. lodestar/fram front a real, running, *better*
substrate: persistent, role-based, lease-gated agents that are observable +
steerable + durably coordinated through the claim graph (raw Agent/Workflow are
ephemeral, unobservable mid-flight, un-steerable).

**This is enforced by a PreToolUse hook** (`fleet-protocol-guard.sh`) that
hard-blocks Agent/Workflow calls. Quick lookups → bash/grep/read inline.
Real work → the protocol below.

## The stack

- **Work queue** = lodestar threads on `:7977` (`ready`/`next`/`leverage`; claim with
  `driver @agent`). **Fleet jurisdiction** = a SEPARATE `:7978` coordinator (presence /
  roles / leases).
- **Spawn**: `~/code/fleet-data/spawn-agent.sh <role[,role]>` — lease-gated roles
  (exclusive → a 2nd holder self-aborts), dormant-until-pinged (~0 idle tokens).
- **Assign/steer by ROLE** (not uuid): `msg-cli.clj <port> send <from> <role> "<task>"`;
  a message IS the steer. **Observe/steer** live via framescope (`:8088`).
- **Concurrency is the engine's job** — fram owns write-serialization + OCC + the `lease`
  primitive (`acquire`/`release`/`fence`); apps express coordination as claims, never
  self-rolled locks. (`driver` = app intent; `lease` = DB mutual-exclusion — never conflate.)
- Recursive teams coordinate peer-to-peer — ALWAYS through the protocol, NEVER
  ultracode/Workflow.

Org brain: FLEET PLAYBOOK = lodestar thread `2026-06-22-232740` (consult first; append
learnings via `lodestar tell 2026-06-22-232740 learning "…"`). How-to:
`~/code/fleet-data/RUNBOOK.md`. Per-repo surface: `~/code/lodestar/CLAUDE.md`.
