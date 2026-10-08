# Estimate details

Separate active execution from queueing, external waits, downloads and checks
when those explain a delay. Keep observation units comparable: version,
workload, cache and hardware can change actual time. Do not derive machine
minutes from a guessed human-time multiplier.

An ETA predicts completion, a checkpoint says when to inspect progress, and a
hard limit sets a resource boundary. At an unexpected delay, inspect the
existing run before deciding it has stalled.

Use the `staffing` skill for the shared worker history and ETA rules.
