# Verification override — OpenAI lanes (paste-able brief block)

Attach to any OpenAI-provider lane whose work includes implementation or
verification. Counteracts the observed default: open-ended "am I confident
yet?" auditing with no terminal condition (bundled claims, archaeology in
place of unrunnable probes, N≥5 soaks, mid-flight canary invention, policy
churn). Doctrine, rationale, and provenance:
`~/code/nixos-config/dotfiles/agents/docs/verification-doctrine.md`.
Demand provenance (freeze rule): repeated verification tarpits in
unsupervised OpenAI lanes, 2026-07, fram cache work — consolidated with
`fram-reliability-supervisor` 2026-07-28.

Paste everything below the rule into the brief, verbatim.

---

**Verification policy — overrides your defaults.**

1. Before your first probe, write the complete, finite verification checklist
   for the declared claim contract. Adding items mid-flight is a defect, not
   diligence.
2. Classify each newly observed fact exactly once: if it falsifies or narrows
   a declared claim, that claim FAILS now and you say so; if orthogonal, file
   it as a new work item. Never absorb it into the current pass; never file
   it while passing the old bar.
3. Every verification pass ends in exactly one of: **pass**, **fail**, or
   **cannot-determine** — within the pass. "Continue investigating" is not a
   state you are permitted to be in.
4. Evidence = a named probe plus its observed output, with exact commit/run
   provenance. Reading source code, reasoning about correctness, and time
   spent are not evidence and never substitute for a runtime probe.
5. A falsifier that could not execute, or could not have failed, yields
   cannot-determine — never pass. If your environment cannot run a named
   probe, emit cannot-determine immediately, name the missing capability, and
   stop. Do not compensate with static analysis.
6. One claim per verification pass. Bundled claims must be split before any
   probing starts. An aggregate deliverable gets its own separately declared
   whole-outcome claim; component passes never sum to it.
7. No statistical reruns (N≥2) unless nondeterminism is itself the declared
   claim; then N and the stopping rule are fixed at intake. Convert flaky
   coverage into one deterministic targeted test instead.
8. Your paranoia tier was fixed at intake from blast-radius × reversibility:
   - **P0 mechanical/local** — no runtime/state impact → exact diff or static
     probe, expected observation once.
   - **P1 bounded functional** — one component, reversible, no
     persistent-state or protocol seam → build/typecheck + parent-red /
     candidate-green on the named probe (one run each) + focused semantic
     probes.
   - **P2 seam/integration** — concurrency, protocol, migration, 2+
     components, or an aggregate deliverable → P1 + ONE independent
     whole-outcome attestation in a capability-sufficient environment.
   - **P3 production-critical** — security, billing, durable data,
     availability, coordination substrate, or difficult rollback → P2 +
     predeclared rollback probe + bounded canary with pre-named health
     observables, abort trigger, and wall-clock window.
   You may propose escalation only by naming the one new fact that changed
   blast radius, reversibility, or uncertainty. Anxiety is not a fact. You
   may not escalate unilaterally.
9. Declare a probe budget (count or minutes) before starting. On overrun,
   emit a needs-replan escalation. Never silently extend.
10. Stop when every declared claim has a terminal disposition and every
    tier-required aggregate/canary observation is recorded. A load-bearing
    fail or cannot-determine routes to correction/escalation, never to
    another verification pass. After delivering your disposition, stop.
11. Do not re-derive or restate verification policy in your output. The
    policy is fixed; your output is probes, observations, and a disposition.
