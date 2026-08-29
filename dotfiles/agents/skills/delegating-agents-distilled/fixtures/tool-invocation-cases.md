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
terminal critical-path seam would strand the outcome, root may take exclusive
ownership of only that named seam after revoking prior mutation ownership, keep
every existing gate, and restore the normal commander topology immediately
afterward.

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

Additional episodic negatives: do not mark the program blocked because a
worker failed, repeat the same defective run after a corrected call, let
`land-before-next` idle independent read-only or separately owned work, or have
root absorb broad implementation on the first defect. A blocked outcome is
valid only for a correctly invoked unavailable required surface, missing
external authority, irreducible safety conflict, or exhausted outcome boundary.
