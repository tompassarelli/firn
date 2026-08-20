---
name: delegating-agents
description: >-
  Decompose, route, dispatch, supervise, steer, and settle delegated agent
  work. Use whenever creating sub-agents or worker lanes, choosing an agent
  model or subscription account, running parallel seams, waiting on another
  actor, setting worker deadlines, replacing a stalled worker, or operating in
  executive orchestration mode.
---

# Delegating agents

Delegate only when independently verifiable work can progress concurrently.
Keep tightly coupled work with one owner.

## Establish continuity and seams

Create or update a restart-grade record in `~/code/todo/` before delegation.
Enumerate the mission's independent units—files, gates, cases, or stages—and
assign one worker per seam, not one worker per mission. A serial edge is valid
only when the later seam consumes the earlier seam's output; write that exact
dependency. Dispatch everything else now, including bounded diagnosis or
preparation beside a held edge.

Give every brief explicit read/write boundaries, a terminal deliverable, the
existing check it owns, an early-exit clause for known capability gaps, and the
authorized supervisor window plus margin. Never invent a tighter deadline or
lengthen one without evidence that legitimate work changed.

## Route models and accounts from evidence

Honor a user-pinned provider, account, model, and reasoning level exactly.
Otherwise use the live configured dispatch surface and provider catalog rather
than remembered availability. An omitted model in a spawn schema is route
metadata, not evidence that a model is unavailable.

Prefer subscription-backed Codex Luna or Terra for bounded and mid-sized
leaves and Sol for hard integration. For a direct OpenAI lane, compose the
North payload, pin model and reasoning on `codex exec`, and use
`codex as <account-id>` when an account is requested. Dispatch the direct CLI
with full access (`--dangerously-bypass-approvals-and-sandbox`) and put its
scope boundary in the brief. If availability is uncertain, inspect installed
configuration and run one fresh subscription-backed probe; an omitted model in
a spawn schema is not a negative result. The bootstrap billing boundary still
applies. Record the assignment and observed outcome in
`~/code/todo/model-assignment-ledger.md`.

## Use the machine without falsifying checks

Run independent lanes concurrently while one-minute load stays below roughly
1.5 times the core count, available memory stays above roughly 8 GiB, and the
machine is not swap-thrashing. Queue the next lane only after a bound is
crossed. Batch compute runs at low scheduling priority. Preserve headroom for
deadline-sensitive checks and timing measurements whose verdict contention
could falsify.

Use smoke to select and interpret checks; do not duplicate its landing or
publication gate rules in worker briefs.

## Supervise every process and worker

Keep a live ledger in which every background shell and worker has one named
purpose, owner, expected progress point, and reap action. Consume a completion
immediately. Silence past the authorized window is a visible failure: verify
the PID and working directory, stop the process, preserve its evidence, and
replace it only with a narrower closer. Never relaunch the same brief blindly
or combine a kill and replacement launch in one command.

Fresh retries use round-unique, line-anchored terminal markers so quoted
history cannot impersonate a live verdict. A probe that reaches a known
capability gap exits within minutes and reports the gap. The same result three
times is a finding, not a polling target.

## Steer and settle

Re-audit every blanket hold: if a held seam cannot name the exact output it
awaits, release it. When a removal is delegated, sweep registrations,
allowlists, paths, pins, locks, tests, and consumer repositories in the same
campaign, then run the final token search across those consumers.

The parent owns integration and settlement. Consume each result, update the
restart record at every externally visible boundary, and use repo-safety to
land and reap verified work. A worker denial changes the path, never the goal;
do not retry verbatim or route around standing law.

In executive mode, decide and act on recorded evidence, keep every ready seam
owned, and notify the operator after the fact in plain language. The standing
grant includes published-release-history repairs only when forcing evidence is
recorded on the coordination board, the chosen path is best supported, and one
chronological tag-to-release mapping remains. This does not broaden safety
authority or permit unrelated mutation.
