---
description: Offload this task to a managed fork — carries your context onto the north roster; this channel never blocks
---

# /offload — context-carrying handoff

Like `/request`, but the fork INHERITS your context. Where `/request` spawns a
fresh lane with only the task text, `/offload` hands the lane a **context brief**
composed from THIS conversation, so it continues where you left off instead of
re-discovering it. Full managed lifecycle (id mint · identity facts · presence ·
completion/death ping) — never the harness-native `/fork`'s invisible zombie.

Your turn is a PASS-THROUGH: compose the brief, one spawn, one confirmation, end
of turn. No inline work.

1. COMPOSE the context brief from your own conversation — crisp, load-bearing
   only:
   - current task state (what is done, what remains),
   - key file paths (`~`-anchored),
   - decisions already made + constraints that bind,
   - the one thing that would waste the fork's time if it re-derived it.
   Keep it tight — a brief, not a transcript dump.
2. SPAWN via `mcp__north__spawn`: model `opus`, effort `high`, role
   `integrator`, posture `deliver`. The prompt carries, in order:
   - `CONTEXT BRIEF:` + the brief from step 1,
   - `FORK TASK:` + the user's directive VERBATIM,
   - the OPERATING CONTRACT: "You carry the coordinator's context above —
     continue the work, do not re-discover it. If it decomposes, fan out
     sub-spawns at the right gaffer dials and supervise (escalation is wired).
     Strictly synchronous; commit checkpoints; never push unless asked; report
     to docs/private/<slug>-report.md; facts vocabulary (never claims)."
   - `AGENT_COORDINATOR` = this session's north id (completion/death pings land
     back here automatically).
3. CONFIRM in ≤3 lines: agent id + `north watch <id>`. END YOUR TURN — never
   wait for the fork.

Only exception: a one-line factual question answerable from THIS session's
context — answer it and say why it wasn't forked.

Task: $ARGUMENTS
