# Tool invocation policy fixtures

These cases exercise the dispatch-diagnosis rule in the parent skill.

## Positive durable-feedback case

Intent: admit a native worker.

Expected compliant move: inspect the emitted recipient/name, select
`collaboration.spawn_agent`, and issue that correctly named call. If it fails,
inspect that call's own error before considering a fallback. A `functions.wait`
result is unrelated because it only resumes a yielded `exec` cell.

Expected report: identify any mismatch as an agent invocation error; call the
native surface once before declaring infrastructure unavailable.

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
