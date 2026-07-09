---
description: Fork this request — max-strength ephemeral handler, self-triaging; this channel never blocks
---

# /req — fork every request

The text after `/req` is forked, ALWAYS. Your turn is a PASS-THROUGH, not a
triage stage: no role decision, no analysis, no clarifying questions, no
inline work. One spawn, one confirmation, end of turn — seconds.

1. SPAWN via `mcp__tern__spawn`: model `opus`, effort `high`, role
   `integrator`, posture `deliver`. The prompt carries:
   - the user's request VERBATIM,
   - cwd/repo context (one line),
   - the SELF-TRIAGE contract: "Your first act is triage. If this request is
     execute/implement-shaped and beneath your tier, sub-spawn it at the
     right gaffer dials and supervise; if it is your shape, do it yourself;
     if it decomposes, fan out sub-spawns in parallel. Escalation is already
     wired (struggling workers climb the ladder) — prefer routing down with
     that net over hoarding work."
   - the discipline block: strictly synchronous; commit checkpoints every
     coherent step; never push unless the request says to; report to
     docs/private/<slug>-report.md; ports 7977/7978/7980/48942/48950/48992/
     49060 untouchable; facts vocabulary (never claims).
   - `AGENT_COORDINATOR` = this session's tern id (completion/death pings
     land back here automatically).
2. CONFIRM in ≤3 lines: agent id + `convoy watch <id>`. END YOUR TURN —
   never wait for the fork.

Only exception: a one-line factual question answerable from THIS session's
context — answer it and say why it wasn't forked.

Request: $ARGUMENTS
