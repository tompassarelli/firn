---
name: delegating-agents
description: >-
  Decompose, route, dispatch, supervise, steer, and settle delegated agent
  work. Use whenever creating sub-agents or worker lanes, choosing an agent
  model or subscription account, running parallel seams, waiting on another
  actor, setting worker deadlines, replacing a stalled worker, or operating in
  executive orchestration mode.
hooks:
  - session-kill-guard
---

# Delegating agents

Delegate only when independently verifiable work can progress concurrently.
Keep tightly coupled work with one closure owner, who owns the outcome rather
than a serial list of defects.

## Establish continuity and seams

Create or update a restart-grade record in `~/code/todo/` before delegation.
Enumerate the mission's independent units—files, gates, cases, or stages—and
assign one worker per seam, not one worker per mission. A serial edge is valid
only when the later seam consumes the earlier seam's output; write that exact
dependency. Dispatch everything else now, including safe preparation beside a
held edge. Explore and evaluate are read-only by default and need no lane;
create one only when a write is admitted.

State the closure posture and its terminal evidence: explore has an observation
or capability gap, evaluate has a decision and its evidence, deliver has the
owned change and named check, preserve has a named artifact/owner/recovery
condition, and prune has proved absence from its named live consumers. Do not
turn a posture into a universal ceremony.

Give every brief explicit read/write boundaries, terminal evidence, the
existing check it owns, an early-exit clause for known capability gaps, and the
authorized supervisor window plus margin. Capability and policy own standing
prohibitions; a brief records only its scoped exception. Never invent a tighter
deadline or lengthen one without evidence that legitimate work changed.

## Route models and accounts from evidence

Honor a user-pinned provider, account, model, and reasoning level exactly.
Otherwise choose model, tier, and deliberation from task difficulty; choose
ceremony and authority separately from blast radius and reversibility. Use the
live configured dispatch surface and provider catalog rather than remembered
availability. An omitted model in a spawn schema is route metadata, not
evidence that a model is unavailable.

Treat North presets as templates, not cages: compose a justified custom route
when its model/deliberation and authority choices are recorded. Prefer
subscription-backed Codex Luna or Terra for bounded and mid-sized leaves and
Sol for hard integration. For a direct OpenAI lane, compose the North payload,
pin model and reasoning on `codex exec`, give the workstream a positive integer
estimated-token budget, and dispatch through `north account dispatch
--assignment <id> --estimated-tokens <n> -- exec ...`. The entry point refreshes
subscription usage, projects each eligible account's utilization from its
observed percentage plus outstanding token reservations through a versioned
per-account/window calibration, records the selected account, atomically
reserves the estimate, and launches `codex as <account-id>` itself. Completion
reconciles the reservation to observed actual tokens; cancellation releases it;
stale reservations expire explicitly. Live agent count is a hard safety cap,
not a substitute score. Round-robin breaks only near ties in projected usage.
Inspect the same decision without launching with `north account dispatch
--dry-run --estimated-tokens <n> --json`. Missing fresh usage, a usable
calibration (including its labeled conservative fallback), the token estimate,
or an eligible account fails closed. Dispatch the direct CLI with full access
(`--dangerously-bypass-approvals-and-sandbox`) and put its scope boundary in the
brief. If availability is uncertain, inspect installed configuration and run
one fresh subscription-backed probe. The bootstrap billing boundary still
applies.

Raw `Agent`, `Task`, Workflow, or collaboration `spawn_agent` calls have no
subscription-account selector and are not fleet-dispatch surfaces. A commander
must not use them when an account is being allocated; use the account-dispatch
entry point above. User-pinned single-account native work remains outside this
fleet rule.

The account-dispatch evidence is live-only commander/operator evidence. It
never becomes Store-authoritative autonomous routing and grants no write or
publication authority; the brief and lane admission still do that. Record the
observed outcome in `~/code/todo/model-assignment-ledger.md`; the API's machine
assignment already records the selected account.

## Admit before dispatch

Mechanically admit model, applicable policy, repository identity, entrypoint,
environment, write authority, and a viable supervisor. A write needs an owned
lane and no conflicting owner; an unadmitted item remains read-only or queued,
not implicitly authorized.

## Use the machine without falsifying checks

The logical DAG says which independent seams may progress. Physical capacity is
separate: use a named compute semaphore when concurrent work could falsify a
timing or resource verdict. Start ready work with fresh CPU/memory headroom,
balanced activity, and round-robin fairness; queue only the constrained compute
edge. Keep one-minute load below roughly 1.5 times the core count, available
memory above roughly 8 GiB, and avoid swap-thrashing. Batch compute runs at low
scheduling priority. Preserve headroom for
deadline-sensitive checks and timing measurements whose verdict contention
could falsify.

Use `verification` to select and interpret checks; do not duplicate its landing or
publication gate rules in worker briefs.

## Supervise every process and worker

Keep a live ledger in which every background shell and worker has one named
purpose, owner, expected progress point, and reap action. Consume a completion
immediately. Silence past the authorized window is a visible failure: verify
the PID and working directory, stop the process, preserve its evidence, and
replace it only with a narrower closer. Never relaunch the same brief blindly
or combine a kill and replacement launch in one command.

Agent Bash background work runs as `run-bounded <duration> -- <command>`, never
as bare `nohup`, `setsid`, `disown`, or an unmanaged `&` job. The duration is
explicit and cannot exceed 24 hours. `run-bounded` owns a transient cgroup and
PID namespace, so owner death and timeout both reap every descendant; all such
jobs share a 48 GiB hard ceiling without reducing compiler parallelism.

Fresh retries use round-unique, line-anchored terminal markers so quoted
history cannot impersonate a live verdict. A probe that reaches a known
capability gap exits within minutes and reports the gap. The same result three
times is a finding, not a polling target.

If the supervisor fails before its child starts, classify infrastructure rather
than a product verdict. When the user bus is unavailable, an explicitly approved
child-free diagnostic may run foreground under `timeout <duration> -- command`;
record that fallback and do not infer child supervision or product success.

## Keep feature liveness safe

Required feature liveness is fail-closed: do not automate feature work or
activation from a missing, stale, or unadmitted signal. The escape is a bounded
repair seam that restores the signal; direct human control may act on the
classified evidence. Neither live-only data nor a failed liveness probe grants
automated authority.

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
