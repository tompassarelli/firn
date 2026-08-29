---
name: delegating-agents-distilled
description: >-
  Decompose, route, dispatch, supervise, steer, and settle delegated agent
  work. Use whenever creating sub-agents or worker lanes, choosing an agent
  model or subscription account, running parallel seams, waiting on another
  actor, setting worker deadlines, replacing a stalled worker, or operating in
  executive orchestration mode.
---

# Delegating agents, distilled

Delegate only independently verifiable seams that can progress concurrently.
Keep tightly coupled work with one closure owner who owns integration and the
outcome.

## Admission and ownership

- Create restart-grade continuity and one forecast/staffing attempt before
  delegation. Name exact dependencies, posture, boundaries, terminal evidence,
  nearest existing check, supervisor window, and reap path.
- Admit model/tier/deliberation, policy, repository identity, entrypoint,
  environment, physical write lane, integration/publication authority, and a
  viable supervisor before dispatch. Unadmitted work remains read-only or
  queued.
- Pass the exact concrete model identity on every provider-native dispatch.
  Never omit it or substitute lineage, ambient, or selection behavior such as
  `self`, `parent`, `default`, or `auto`; if runtime evidence cannot name the
  model, do not dispatch and do not guess.
- Write authority is exclusive per physical checkout. Separate worktrees may
  host overlapping candidates, but one integration owner and landing order must
  exist before publication; later candidates reconcile onto the exact landed
  object and rerun affected checks.
- Treat `land-before-next` as a mutation dependency: serialize overlapping
  writes and consumers of the exact landed artifact, while independent
  read-only or separately owned ready work continues.
- Use the smallest inherited context that preserves uncaptured decisions.
  Workers read applicable source instructions themselves.
- Propagate applicable source authority into every worker brief and admit the
  runtime and backend separately. Source authority selects the typed authoring
  profile; runtime and backend select execution. The source-authority policy
  constrains `domainRequirements`; runtime and backend remain consumer-owned
  execution facts. Do not add to or replace the exactly eight portable routing
  fields.

## Time, route, and safety decisions

- Budget elapsed critical-path wall time separately from summed agent execution
  time. Stop adding workers at planned aggregate agent time without a closure
  candidate; at twice either estimate interrupt and rebrief. Renaming or
  replacing an attempt does not reset the operator outcome clock.
- Select capability from task difficulty and oracle strength; select ceremony
  and authority separately. Honor every operator pin exactly and use the live
  provider catalog. Account allocation requires the sanctioned North dispatch
  entrypoint, a positive token estimate, recorded assignment, and full worker
  authority; a native spawn is not an account-allocation surface.
- Parallelism must shorten the critical path after setup, merge, review, and
  compute cost. Race only independent lanes against one predeclared acceptance
  gate; consume the first verified winner and reap losers.
- Use a compute semaphore when contention could falsify a verdict. Background
  work must be bounded, named, supervised, and reaped. Do not retry the same
  failed brief blindly; three identical results are a finding.

## Tool-call correctness

- Before declaring a dispatch, wait, or capability surface unavailable, compare
  the intended operation with the actual emitted recipient and tool name, then
  read that tool's error. A failure from a different tool proves an invocation
  error, not target infrastructure failure.
- Native agent operations use the `collaboration.*` namespace:
  `collaboration.spawn_agent` admits a child;
  `collaboration.followup_task` reactivates or steers an idle child;
  `collaboration.send_message` delivers without triggering a turn;
  `collaboration.interrupt_agent` interrupts;
  `collaboration.list_agents` inspects fleet state; and
  `collaboration.wait_agent` waits for agent updates. `functions.wait` only
  resumes a yielded `exec` cell, while
  `request_user_input` is a human-question surface; neither is a dispatch or
  agent-wait operation.
- After one wrong-recipient or misnamed call, inspect its error and the available
  tool catalog, then make exactly one minimal, correctly named native
  collaboration control call to the intended surface. Do not switch fallback
  transports, widen architecture, or mark a blocker until that target surface
  itself fails. Reports must distinguish an agent invocation error from an
  infrastructure error.
- If the same run repeats a recipient/name mismatch after that correction,
  preserve the evidence, quarantine or retire the run, and admit a replacement
  under the original bounds. Apply the same replace-with-new-evidence rule to a
  worker defect. Neither failure blocks the product goal; drive the replacement
  and every other ready front within the original outcome clock.

## Runtime incidents

Detect unexplained admission, startup, death, liveness, control, or reporting
anomalies, preserve their bounded evidence, and hand the bounded event evidence
to `agent-runtime-incident-distilled` while authorized containment and
replacement continue. A repeated recipient/name mismatch and admitted worker
death or silence are incident signals. That incident skill alone owns
deduplication, lifecycle transitions, and reliability closure. Route fallback
admission to `executive-orchestration-distilled` and route every
reliability-closure decision back to the incident skill.

## Continuous supervision

- Treat dispatch as the start of ownership, not completion. A status answer
  never releases ownership or turns an active workstream into an
  operator-driven polling loop.
- Continue bounded waits while workers or processes remain live, and drive
  every ready in-scope action without requiring another operator ping.
  Unchanged live state is expected and is not a blocker.
- When silence passes the admitted supervisor window, check liveness and then
  steer, interrupt, or replace the attempt within existing authority. Preserve
  evidence and never turn an unchanged wait into a blind retry.
- End ownership only when the outcome is complete, an exact operator decision
  is required for remaining progress, or one of the bounded stop conditions
  below is reached. Continue unrelated ready work before requesting a decision.

## Minimum delegation workflow

1. Decompose to independent seams and appoint the nearest closure owner.
2. Record continuity, attempt budgets, posture, authority, evidence, and checks.
3. Route and dispatch every ready seam; keep serial consumers waiting only for
   the exact artifact they consume.
4. Supervise progress against authorized windows, steer with new evidence, and
   consume terminal reports immediately.
5. The closure owner decides verification, review, integration, publication,
   debt, race, and lane state; then emits an immutable SettlementCard and uses
   a fresh `settle-work-distilled` clerk for mechanical bookkeeping.
6. Update continuity prose, land through repository safety, and reap released
   workers, processes, lanes, branches, and claims.

Quarantine the affected seam, not the program, on an unavailable required
authority surface, ambiguous product owner, missing liveness signal for
automated activation, exhausted outcome budget, or a worker result that lacks
exact terminal evidence; an unsettled child blocks settlement only. Continue
unrelated ready work and apply the continuous-supervision stop rule.

Reserve a blocked outcome for a correctly invoked unavailable required surface,
missing external authority, an irreducible safety conflict, or a genuinely
exhausted outcome boundary. A local routing mistake, invocation error, worker
failure, unchanged wait, or failed replacement attempt is not blocking
evidence. When executive replacement admission fails, route any request for
bounded root fallback to `executive-orchestration-distilled`; otherwise report
the exact gap without lowering a safety boundary or inventing success.

Stock-role and settlement details live in the reference skill; load it only for
an explicit request or a named unresolved detail, per the always-loaded policy.
