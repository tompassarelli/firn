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
- **The reflex also fires at DESIGN time — catch it there.** Never write
  "sequential runs / no other work on the machine during trials" into an
  experiment protocol or pre-registration without a MEASUREMENT justifying it.
  The default protocol is: maximum safe parallelism (real limits only — port
  collisions, API caps), disjoint `taskset` pins, loadavg recorded per run in
  conditions.txt, a pre-stated contamination threshold with discard-and-rerun.
  (EXP-021 2026-07-03: sequential 6-run pipeline written unmeasured into a
  frozen DESIGN; measurement showed runs network-bound at ~35% load — halved
  wall-clock by pairing arms, which is also FAIRER: within-pair conditions are
  identical for the ratio metric.)
- **The standard isolation tool on whiterabbit is `bench-shield`**
  (`nixos-config:modules/bench-shield/`): `bench-shield on` confines
  everything else to cores 0-11 (runtime cgroup cpusets, reboot clears), then
  run the experiment with `taskset -c 12-23 <cmd>` — kernel-enforced exclusive
  cores, no root needed for the run itself. `off` releases. Prefer this over
  cloud boxes (shared-tenancy steal time is a WORSE timing confound) and over
  `isolcpus=` (static, wastes idle cores).
- **A frozen protocol that encodes the reflex is not sacred.** Measure, then
  fix it the compliant way — a dated pre-run amendment — and parallelize.
  For A/B arms specifically: running both arms SIMULTANEOUSLY beats
  interleaved-sequential (each arm faces identical machine + API conditions);
  serialization is the less rigorous design, not the safer one.
