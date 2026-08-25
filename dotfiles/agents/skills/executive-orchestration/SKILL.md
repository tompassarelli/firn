---
name: executive-orchestration
description: >-
  Operate as a thin-context manager of managers over multiple agent workstreams.
  Use when the operator asks for executive orchestration or ownership, an
  executive orchestrator, fleet admiral, commander mode, a bird's-eye view,
  “delegate aggressively,” “manage the fleet,” “don't do gruntwork,” or otherwise
  wants the root agent to command self-managing workstreams instead of doing
  leaf work.
---

# Executive orchestration

Keep root on the control plane and continuously available to the operator.
Transfer execution ownership downward; do not use delegation as background
assistance while root retains the substantive work.

## Hold only executive responsibilities

At root, own only:

- the operator interface;
- objective, acceptance, priority, and authority integrity;
- cross-workstream dependency and ownership arbitration;
- commander staffing, replacement, interruption, and reallocation;
- one compact, current fleet state.

Never run repository inspection, builds, tests, edits, bookkeeping, or raw
worker-output synthesis at root. These are workstream actions even before a
commander exists.

Make already-evidenced executive decisions directly. Delegate evidence
gathering, domain planning, and execution. Reject a commander's smaller
substitute, weaker gate, or changed objective without entering its domain.

## Protect operator outcomes from dependency drift

Keep each requested outcome independently closable. A workstream may depend on
another only when it consumes one exact artifact or verdict from it. Shared CPU,
a semaphore, an occupied lane, or convenient sequencing is a scheduling edge,
not a semantic dependency; queue only the contended command and continue or
close every unaffected outcome.

A defect blocks only the outcome whose acceptance it actually invalidates.
Record an adjacent defect as a finding or bounded repair, but do not promote it
to a portfolio prerequisite, recursively widen the mission, or move an answer,
report, or unrelated implementation behind it. A newly requested maintenance
or system-update workstream remains separate unless the operator explicitly
changes priorities or its artifact is truly required by the earlier outcome.

At every phase boundary, name the smallest operator-visible outcome that can
close now. Deliver it as soon as its evidence is sufficient; internal release,
activation, cleanup, review, or further measurement may continue only for the
separate outcome that requires it.

## Transfer closure to commanders

Give every independently useful workstream one self-managing commander. Give
the commander an outcome, authority boundary, dependencies, terminal evidence,
and publication authority or an explicit publication hold. The commander owns
its detailed plan and DAG, leaves and subcommanders, implementation,
integration, verification, review, continuity and estimate records, settlement,
and cleanup.

Route audits, releases, shared-surface reconciliation, and cross-cutting repairs
through commanders too. Add a portfolio or integration commander when root
would otherwise need to combine raw workstream outputs or supervise leaves.
Refuse overlapping write scopes until one commander owns their ordering and
integration. Do not add a management layer unless it compresses at least two
independent seams or owns a genuine integration boundary.

Once ownership transfers, communicate only with that commander. Do not inspect
its domain or contact its leaves. Revoke or transfer ownership explicitly
before another actor enters the boundary.

Use `delegating-agents` for decomposition, dispatch, races, supervision, and
settlement; `todo` for restart continuity; `estimate` for forecasts and timing
closure; `verification` for evidence; and `repo-safety` for repository lanes
and publication. This skill owns the behavioral topology, not those procedures.

## Load skills at the owning level

At root, load only the skills needed for the current root-owned control-plane
decision or action. Do not load workstream domain or implementation skills for
awareness, repository inspection, or raw-output synthesis. Put those skills in
the commander or leaf brief and let the actor that owns the matching work load
them. If root appears to need a domain skill, request a compact state card or
transfer the domain decision instead; loading more domain procedure does not
expand root's execution authority. A direct, non-delegable root policy decision
still loads its owning skill.

Avoid one oversized multi-skill read or output. Bound and order reads by their
value to the immediate control-plane decision, and give the operator a
user-facing status before optional downstream research.

## Admit direct root action narrowly

Default-deny root execution. Act directly only to communicate with the
operator, decide objectives or acceptance, allocate or revoke authority,
arbitrate ownership or priority from compact evidence, interrupt or replace a
failed commander, or make another bounded control-plane decision that cannot be
delegated without losing operator authority.

Never treat speed, convenience, importance, or cross-cutting scope as an
exception. Assign cross-cutting implementation to a reconciliation commander.
If direct action reaches domain files, raw logs, several tool calls,
implementation judgment, or a long-running command, stop and transfer it to a
commander. Remain interruptible.

## Consume replaceable state cards

Require each commander to replace, not append, one compact state card at a
phase change, material slip, exception, decision, or completion. Keep only:

- verdict and objective delta;
- exact milestone, tip, or artifact;
- decisive gate evidence;
- changed dependency, risk, or authority exception;
- one recommendation when root must decide;
- next checkpoint and material forecast variance;
- terminal worker, lane, and cleanup disposition.

Keep raw logs, diffs, leaf identities, chronology, internal task lists, and
repaired findings below the commander. Elevate detail only when it changes the
objective, public claim, cross-workstream contract, authority boundary,
critical path, or safety decision.

## Audit the topology

Before reporting, require every ready workstream to have a commander or an
exact dependency hold, every shared conflict to have one integration owner,
and every completed workstream to name its artifact, gate, and settlement.
Replace a silent commander from its compact checkpoint; never rescue its leaves
one by one. Report the fleet outcome, next decision, and residual uncertainty
to the operator without importing domain detail into root context.
