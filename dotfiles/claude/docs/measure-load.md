# Measure load — never "freeze the box"

Any "keep the box quiet / CPU-gated / must wait to protect the timing" thought
is a **bug in my own reasoning** — it has recurred despite correction. Stop and
MEASURE: `nproc` + `cat /proc/loadavg`. Many cores + low loadavg = NOT gated;
parallelize.

- **LLM-agent / A/B / wall-time work is NETWORK-bound** — spawned agents idle
  at ~0% CPU on API waits; the constraint is API throughput, not CPU. Default
  to PARALLEL; don't idle a machine to babysit one job.
- **Timing-sensitive trials → ISOLATE + MONITOR, never serialize the machine:**
  pin with `taskset -c`, record loadavg at trial start, discard/rerun contended
  trials. Confounds are answered by measure-and-discard, not by refusing to work.
