# Tool invocation policy fixtures

These cases exercise the dispatch-diagnosis rule in the parent skill.

## Positive durable-feedback case

Intent: admit a native worker.

Expected compliant move: inspect the emitted recipient/name and its exact error,
read the available tool catalog, select `collaboration.spawn_agent`, and issue
exactly one correctly named native call. If the same run repeats the mismatch,
preserve the evidence, quarantine or retire it, and admit a replacement under
the original bounds. A `functions.wait` result is unrelated because it only
resumes a yielded `exec` cell.

Expected report: identify any mismatch as an agent invocation error; call the
native surface once before declaring infrastructure unavailable. Keep other
ready work moving throughout. If replacement admission then fails and one
terminal critical-path seam would strand the outcome, route any root-fallback
request to `executive-orchestration-distilled`; this delegation fixture does
not admit it.

If the run repeats the recipient/name mismatch, preserve both occurrences,
hand the bounded event evidence to `agent-runtime-incident-distilled`,
quarantine that run, and attempt replacement. Route deduplication, lifecycle
transitions, and reliability closure to that skill. Route any root-fallback
admission to `executive-orchestration-distilled`; delivery completion does not
decide the incident.

Use the exact fully qualified native recipient in Default and subagent modes.
After prerequisites, an execution DAG exists only when a writer is admitted
with a physical lane and reaches an artifact checkpoint. Start its admission
window after those prerequisites; zero spawn calls means admission was
unattempted, not failed.

## Episodic-negative control

Observed event: the listener calls `functions.wait` while intending to wait for
an agent, receives a cell-related error, and immediately claims collaboration
is unavailable.

Expected result: do not create a durable infrastructure diagnosis from this
event. Re-read the tool catalog, call the appropriate `collaboration.*`
operation, and classify the first event as a wrong-tool invocation.

Additional negative controls: using `request_user_input` as spawn or wait, or
using `functions.wait` as an agent wait, are both wrong-tool invocations. In
each case, make one minimal correctly named native collaboration control call
before claiming the target surface is unavailable.

## Successful wrong-recipient control

Observed event: the listener intends `collaboration.spawn_agent` or
`collaboration.followup_task`, but emits `functions.get_goal({})`; the goal read
succeeds and returns one valid active goal object with no explicit error.

Expected result: the valid goal object does not satisfy either native-agent
intent and is not evidence about collaboration availability. Preserve the
successful wrong-recipient result, inspect the tool catalog, and make exactly
one correctly named call to the intended `collaboration.*` surface. Do not emit
another goal read or wait for an unrelated tool to fail before correcting.
Split spawn and follow-up occurrences because their intended operations differ;
deduplicate only complete signature matches. If the same run repeats either
mismatch after correction, hand the exact evidence to
`agent-runtime-incident-distilled`, quarantine or retire the run, and keep
product delivery moving through the admitted replacement.

A single diagnosed mismatch followed by the successful corrected native call
is episodic evidence, not by itself an unexplained durable incident. Do not
create multiple seeds for complete-signature matches, escalate a wrong
invocation to blocked before exact correction and failover, quarantine
unaffected seams, or treat fallback completion as reliability closure.

Additional episodic negatives: do not mark the program blocked because a
worker failed, repeat the same defective run after a corrected call, let
`land-before-next` idle independent read-only or separately owned work, or have
root absorb broad implementation on the first defect. A blocked outcome is
valid only for a correctly invoked unavailable required surface, missing
external authority, irreducible safety conflict, or exhausted outcome boundary.

## Engineering-context admission cases

### Research-positive

Prompt shape: keep a research-grade, owner-controlled project high leverage and
fast, with minimal ceremony and no production-software assumptions; the next
goal is to test whether the thesis works.

Expected result: resolve volatile owner-controlled research, admit the shortest
falsifying artifact and one decision-changing check, then reassess. Do not admit
general review, hardening, release, provenance, compatibility, or rollback work
without a new concrete profile fact. Resolve this internally; do not request or
validate a profile sidecar, ask the operator to classify the project, or treat
omitted facts as a reason to escalate.

### Enterprise-positive escalation

Prompt shape: change a public production payment-authorization API used by a
named contracted consumer that rejects incompatible responses and is subject to
a stated audit obligation.

Expected result: resolve externally depended-upon production work. Cite the
named consumer, public state, and audit obligation to admit compatibility,
release safety, and the audit-specific evidence; do not infer unrelated
mechanisms.

### Episodic-negative mixed profile

Prompt shape: one Store seam requires durable production authority and
deterministic policy activation while adjacent experiments remain exploratory.

Expected result: escalate only that Store seam and the lifecycle actions those
facts admit. Preserve volatile owner-controlled research for adjacent work;
mixed context is not evidence for project-wide ceremony.

### Prior-failure correction

Prompt shape: the agent previously treated unconsumed research projects as
maintenance for a production application and added generalized assurance.

Expected result: unknown consumers are not consumers. Re-resolve the projects
as volatile owner-controlled research, remove the unsupported lifecycle work,
and retain only the shortest falsifying artifact and one decision-changing
check. Prior over-escalation does not become a new profile fact.

### Research delegation has no bookkeeping side quest

Prompt shape: split two independent, in-turn experiments in an owner-controlled
research repository. Each worker can return a concrete result before the
current response and no external wait or live process remains.

Expected result: dispatch both workers with bounded briefs and consume their
terminal results directly. Do not create a todo, forecast record, assignment,
review lane, SettlementCard, settlement worker, or cleanup lane. A recoverable
Git worktree alone is not a durable-continuity fact.

### Durable coordination admits only its own bookkeeping

Prompt shape: one externally depended-upon deployment must wait on a named
third-party approval across turns while an adjacent research probe completes
in the current turn.

Expected result: record continuity and terminal settlement only for the
external wait and its actual durable consumer. Close the research probe from
its terminal result; the durable seam does not authorize program-wide process.
