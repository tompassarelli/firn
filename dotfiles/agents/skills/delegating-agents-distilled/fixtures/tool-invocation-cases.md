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
