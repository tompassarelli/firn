---
description: Non-blocking request — fork it to a handler agent immediately, keep this channel free
---

# /req — fork this request, unblock the channel

The text after `/req` is a REQUEST TO FORK, not a request to execute here.
Your job is INTAKE ONLY, and it must be fast: one triage decision, one spawn,
one confirmation line. No analysis, no clarifying questions, no inline work.

1. TRIAGE (seconds, not deliberation) — pick the gaffer role by task shape:
   mechanical/fully-specified → executor · one feature in known patterns →
   implementer · cross-file/ambiguous/foundational → integrator · "how/why/
   investigate" → analyst · "find/collect" → researcher. When torn between
   two, take the higher tier. Do not read files to decide.
2. SPAWN via `mcp__tern__spawn` with that role's pinned dials (the gaffer
   table), `posture` per role, and a prompt that contains: the user's request
   VERBATIM, the cwd/repo, the standing discipline block (strictly
   synchronous; commit checkpoints; never push unless the request says to;
   report to docs/private/<slug>-report.md), and `AGENT_COORDINATOR` = this
   session's tern id so completion pings land back here.
3. CONFIRM in ≤3 lines: agent id, role@dials, and the watch command
   (`convoy watch <id>`). Then END YOUR TURN. Do not wait for the worker.

If the request is genuinely un-forkable (it needs an answer from THIS
session's context, or it's a one-line factual question), answer it directly
and say why it wasn't forked — that is the only exception.

Request: $ARGUMENTS
