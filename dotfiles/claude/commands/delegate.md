---
description: Delegate this request to a managed lane — context is a parameter (context:all carries this session's brief; context:none starts fresh); this channel never blocks
---

# /delegate — the one delegation verb

Every work request delegates (constitution: "The supervisor never blocks — the
user talks to a listener, never a worker"). The only variable is the CONTEXT
DIAL, an optional leading token on `$ARGUMENTS`:

- `context:all` — fork-of-the-supervisor: compose a brief from THIS conversation
  and attach it, so the lane continues where you left off.
- `context:none` — fresh lane, right-sized, no baggage: task text only.
- ABSENT — YOU choose the dial per the constitution: does this task need this
  session's context to proceed? → `context:all`; is it self-contained / ad-hoc?
  → `context:none`. State which you picked and why, in one clause.

Your turn is a PASS-THROUGH, not a triage stage: no role decision, no analysis,
no clarifying questions, no inline work. (context:all adds ONE step — compose the
brief.) One spawn, one confirmation, end of turn — seconds.

1. IF context:all — COMPOSE the context brief from your own conversation — crisp,
   load-bearing only:
   - current task state (what is done, what remains),
   - key file paths (`~`-anchored),
   - decisions already made + constraints that bind,
   - the one thing that would waste the lane's time if it re-derived it.
   Keep it tight — a brief, not a transcript dump. (context:none — skip; task
   text only.)
2. SPAWN via `mcp__north__spawn`: model `opus`, effort `high`, role `integrator`,
   posture `deliver`. The prompt carries, in order:
   - `CONTEXT BRIEF:` + the brief from step 1 (context:all only),
   - `DELEGATE TASK:` + the user's directive VERBATIM,
   - cwd/repo context (one line),
   - the OPERATING CONTRACT / SELF-TRIAGE: "Your first act is triage. If this is
     execute/implement-shaped and beneath your tier, sub-spawn it at the right
     gaffer dials and supervise; if it is your shape, do it yourself; if it
     decomposes, fan out sub-spawns in parallel. Escalation is already wired
     (struggling workers climb the ladder) — prefer routing down with that net
     over hoarding work. (context:all: You carry the coordinator's context above —
     continue the work, do not re-discover it.) Strictly synchronous; commit
     checkpoints every coherent step; never push unless the request says to;
     report to docs/private/<slug>-report.md; ports 7977/7978/7980/48942/48950/
     48992/49060 untouchable; facts vocabulary (never claims)."
   - `AGENT_COORDINATOR` = this session's north id (completion/death pings land
     back here automatically).
3. CONFIRM in ≤3 lines: agent id + `north watch <id>`. END YOUR TURN — never wait
   for the lane.

Only exception: a one-line factual question answerable from THIS session's
context — answer it and say why it wasn't delegated.

Request: $ARGUMENTS
