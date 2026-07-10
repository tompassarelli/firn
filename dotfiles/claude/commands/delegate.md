---
description: Delegate this request to a managed lane — this session's context rides along by default; --new = empty-context lane; this channel never blocks
---

# /delegate — the one delegation verb

Every work request delegates (constitution: "The supervisor never blocks — the
user talks to a listener, never a worker"). The only decision is BINARY: include
this session's context, y/n — context rides along BY DEFAULT; a trailing
`--new` flag on `$ARGUMENTS` opts out (same word the harness uses for
"session with empty context"):

- **`/delegate <task> --new`** — empty context: compose a right-sized prompt (a good
  prompt IS the context; more context = a bigger prompt, judgment only). A fresh
  lane, no baggage.
- **default `/delegate <task>`** — carry this session forward: a mechanical
  full session fork (SDK resume-fork; the transcript-inject brief below is the
  fallback realization), so the lane continues where you left off.

Absent the flag, YOU decide per task: does this need THIS session's context to
proceed? → default; self-contained / ad-hoc? → `--new`. State which and why,
in one clause.

Your turn is a PASS-THROUGH, not a triage stage: no role decision, no analysis,
no clarifying questions, no inline work. (the default adds ONE step — carry
the context.) One spawn, one confirmation, end of turn — seconds.

1. IF context rides (default, no `--new`) — carry this session forward. Transcript-inject
   realization: COMPOSE a context brief from your own conversation — crisp,
   load-bearing only:
   - current task state (what is done, what remains),
   - reference existing artifacts — reports, specs, commits, diffs — by
     `~`-anchored path; don't restate their content,
   - decisions already made + constraints that bind,
   - redact secrets/keys/PII from the brief,
   - where the continuation has a clear shape, name the suggested gaffer role
     for it,
   - the one thing that would waste the lane's time if it re-derived it.
   Keep it tight — a brief, not a transcript dump. (bare — skip; task text only.)
2. SPAWN via `mcp__north__spawn` as the ORCHESTRATOR tier. Resolve the model
   MECHANICALLY by the Fable window — run `date -u +%Y-%m-%dT%H:%M:%SZ`: if the
   result is before `2026-07-12T16:00:00Z` (window OPEN) → model `fable`, effort
   `high`; otherwise → model `opus`, effort `xhigh`. Do NOT pass a worker
   `role`/`posture` — the orchestrator contract rides in the prompt below, and a
   worker posture block would inject the interned "don't sub-delegate" clause and
   contradict fan-out. The prompt carries, in order:
   - `CONTEXT BRIEF:` + the brief from step 1 (default mode only),
   - `DELEGATE TASK:` + the user's directive VERBATIM,
   - cwd/repo context (one line),
   - the OPERATING CONTRACT (two-tier law): "Decide your TIER by the task's shape
     — there is no third tier below you. DECOMPOSES (≥2 independent subtasks) ⇒
     you are the ORCHESTRATOR: fan out one sub-spawn per subtask, in parallel,
     THIS turn, at the right gaffer dials; do NOT execute subtasks yourself —
     read/analyze, spawn, steer, verify, integrate; give each sub-brief steps
     that end on a checkable done-bar (a command + expected output, or a grep +
     expected hit count); own the seams and verify each worker AGAINST ITS
     done-bars — a bare 'done' is never accepted. Decompose by the STOP-RULE:
     split only while further subdivision increases independence, certainty, or
     verifiability more than it increases integration cost — integration is the
     expensive part; a subtask is TERMINAL (stop splitting) when it has a clear
     objective, bounded scope, known inputs/outputs, and a verification path.
     Give each sub-spawn that LOCAL contract. YOU own the REDUCTION: child
     outputs return to you and reconcile in you — never flat fan-in to a
     synthesizer; convergence mirrors decomposition. CHECKPOINT DISCIPLINE (a
     silent reduce phase is how orchestrators wedge): your FIRST act is a report
     skeleton in docs/private/ + the fan-out, both within your first 3 turns;
     keep turns SHORT thereafter, appending each worker's result to the skeleton
     AS it returns — partial state stays on disk and a stall is caught early,
     never lost to silence. Over-parallelize
     exploration, aggressively converge execution; width and sequential waves
     (explore wave → reconcile → execute wave) are open — depth stays two.
     ATOMIC ⇒ you are the INTERNED WORKER: own it
     end-to-end and do NOT sub-delegate, except spawning ONE verifier for your own
     deliverable — no worker spawns workers; your deliverable returns UP to the
     orchestrator that spawned you. Escalation is wired (struggling
     workers climb the ladder). (default mode: You carry the coordinator's context
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
