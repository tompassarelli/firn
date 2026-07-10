---
description: Delegate this request to a managed lane — bare = right-sized fresh prompt; --with-context = carry this session forward; this channel never blocks
---

# /delegate — the one delegation verb

Every work request delegates (constitution: "The supervisor never blocks — the
user talks to a listener, never a worker"). The only decision is BINARY: include
this session's context, y/n — expressed as a trailing `--with-context` flag on
`$ARGUMENTS`:

- **bare `/delegate <task>`** — NO context: compose a right-sized prompt (a good
  prompt IS the context; more context = a bigger prompt, judgment only). A fresh
  lane, no baggage.
- **`/delegate <task> --with-context`** — carry this session forward: a mechanical
  full session fork (SDK resume-fork; the transcript-inject brief below is the
  fallback realization), so the lane continues where you left off.

Absent the flag, YOU decide per task: does this need THIS session's context to
proceed? → `--with-context`; self-contained / ad-hoc? → bare. State which and why,
in one clause.

Your turn is a PASS-THROUGH, not a triage stage: no role decision, no analysis,
no clarifying questions, no inline work. (`--with-context` adds ONE step — carry
the context.) One spawn, one confirmation, end of turn — seconds.

1. IF `--with-context` — carry this session forward. Transcript-inject
   realization: COMPOSE a context brief from your own conversation — crisp,
   load-bearing only:
   - current task state (what is done, what remains),
   - key file paths (`~`-anchored),
   - decisions already made + constraints that bind,
   - the one thing that would waste the lane's time if it re-derived it.
   Keep it tight — a brief, not a transcript dump. (bare — skip; task text only.)
2. SPAWN via `mcp__north__spawn`: model `opus`, effort `high`, role `integrator`,
   posture `deliver`. The prompt carries, in order:
   - `CONTEXT BRIEF:` + the brief from step 1 (`--with-context` only),
   - `DELEGATE TASK:` + the user's directive VERBATIM,
   - cwd/repo context (one line),
   - the OPERATING CONTRACT / SELF-TRIAGE: "Your first act is triage. If this is
     execute/implement-shaped and beneath your tier, sub-spawn it at the right
     gaffer dials and supervise; if it is your shape, do it yourself; if it
     decomposes, fan out sub-spawns in parallel. Escalation is already wired
     (struggling workers climb the ladder) — prefer routing down with that net
     over hoarding work. (--with-context: You carry the coordinator's context
     above — continue the work, do not re-discover it.) Strictly synchronous;
     commit checkpoints every coherent step; never push unless the request says
     to; report to docs/private/<slug>-report.md; ports 7977/7978/7980/48942/
     48950/48992/49060 untouchable; facts vocabulary (never claims)."
   - `AGENT_COORDINATOR` = this session's north id (completion/death pings land
     back here automatically).
3. CONFIRM in ≤3 lines: agent id + `north watch <id>`. END YOUR TURN — never wait
   for the lane.

Only exception: a one-line factual question answerable from THIS session's
context — answer it and say why it wasn't delegated.

Request: $ARGUMENTS
