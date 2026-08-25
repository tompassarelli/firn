---
name: verification
description: >-
  Select, run, supervise, and interpret proportionate evidence. Use for tests,
  checks, compile/build/format/generation loops, debugging reproductions, bug
  validation, CI, release preflight, performance measurements, or any claim
  that work is proved, passing, fixed, stable, or ready to publish.
---

# Verification

Choose a profile before running a check. State the claim and what pass or fail
changes. If both outcomes lead to the same action, do not run it. Stop as soon
as the named decision is made.

## Price every development loop

Before each compile, test, build, format, generation, or equivalent development-loop invocation, including the first, determine internally the decision it can change, expected wall time and its measured or explicit prior, remaining invocations `N >= 1`, smallest credible optimization cost `C`, expected saving per invocation `S`, break-even `ceil(C/S)`, and `run` or `optimize`. Count the current invocation in `N`; use a conservative estimate when history is absent. If no credible optimization is available, record `C=none`, `S=0`, and `break-even=never`. Optimize first when break-even fits within remaining uses or expected interactive latency is itself unacceptable. Optimization may eliminate repeated work but must preserve the decision instrument's evidence strength. Supervise the run and stop it at twice the expected duration; preserve output and diagnose the expectation, contention, infrastructure, or product cause before any retry or timeout change. Compare actual with expected and use the observation to price the next invocation.

Routine pricing is internal. Do not serialize work or add visible structured preflight chatter solely to report it. Surface it when an overrun, optimization decision, or changed result affects the work, or when the user asks for it.

## Record loop outcomes

Capture each invocation's actual wall time, actual-to-expected ratio, outcome, classified overrun cause, and measured saving under the same task-local loop ID when available without serial work. Keep routine telemetry internal or opportunistic; do not record raw commands, inputs, or secrets. Surface and classify every run over twice expectation before any retry or timeout change. Surface an optimization when its break-even fits the remaining uses, and never weaken evidence to gain time.

At handoff, report at most a compact, meaningful aggregate when it changes the reader's understanding: loop class, run count, material overrun or optimization, and realized net saving. Include p50 and p95 only when at least 20 observations make them informative. Do not manufacture a campaign report for routine clean runs. Use the first observations as the baseline and require recurring loop latency and realized net saving to improve rather than merely producing more telemetry.

## Choose the profile

| Profile | Use | Evidence |
| --- | --- | --- |
| `explore` | Research or prototype | Use the cheapest falsifier. Add observability when it helps learning. Do not run a regression suite. |
| `deliver` | Default for reversible work | Run one nearest affected deterministic seam or controlled integration check, then land. A tiny or local edit must not trigger the whole test suite. |
| `stabilize` | Maintenance or genuinely cross-cutting integration | Run the affected suite or shard. Add at most one named journey, and only when the scope requires it. |
| `release` | Publication is the next action | Run the repository's local non-publishing preflight for the exact commit to publish. |
| `critical` | Security, durable data integrity, irreversible migration or effect, or a published contract | Name the threat or failure and collect proportionate targeted evidence. Do not default to maximal testing. |

For a final release, a failed candidate consumes no final version. Repair it
and reuse that version. Any authorized public-history repair must leave one
chronological tag-to-release mapping.

Do not silently escalate profiles. A new reproducible product defect may block;
an observation does not create a new acceptance criterion.

## Select a decision instrument

Use the lowest deterministic layer that can prove the claim. `L0` is a pure
rule, static fact, parser, formatter, or one narrow seam. `L1` is one controlled
integration boundary. `L2` is one named end-to-end journey whose result opens a
consequential action. `L3` is the exact-commit local non-publishing release
preflight.

Keep unrelated claims in separate instruments. Control owned clocks,
randomness, state, versions, and dependencies where they affect the verdict.
When verdict-sensitive, identify the actual producer, consumer, and artifact
identity rather than inferring them from a name or path. If a route is blocked,
use one independent evidence route or record the exact capability gap; do not
substitute speculation for a verdict.
For a performance claim, define the metric and decision threshold first and
isolate contention that could falsify the measurement. Before interpreting
probe overhead, compare a matched uninstrumented A/B run; remove temporary
instrumentation when the decision is made.

## Bound provenance to the decision

Require provenance only when substituting a different producer or artifact
could change the decision. Name that counterfactual first, then verify one
producer → artifact → consumer edge at the nearest existing boundary. Reuse the
workflow's version output, checkout identity, release manifest, activation
record, or other existing authority; do not invent a stronger lineage system.

For exploration, diagnosis, status, and directional measurement, record the
observed command and readily available version or revision, then report any
identity uncertainty as a caveat. For release or `critical` work, require the
exact commit, digest, signature, or activation identity only when the named
publication or irreversible action consumes that identity. A missing or
malformed identity proof blocks only that consuming action.

Do not recursively attest the attestor, traverse package or derivation graphs,
normalize competing metadata schemas, or create immutable-package ceremony
unless the governing acceptance contract or named threat requires that exact
proof. If existing metadata cannot answer the required identity question,
report the capability gap instead of building an attestation subsystem. Never
move an answer, direct observation, or unrelated workstream behind provenance
repair.

## Measure directly before building a harness

For a status, diagnosis, or directional performance decision, start with the
cheapest existing direct command: one cold observation and at most three
representative warm or edit observations. Report the observed range and its
environmental caveats. Do not require a tail statistic or release-grade
campaign when those direct observations already decide the question. Escalate
to a larger sample only when a predeclared threshold or tail claim can change
the action.

Admit a new harness only when the direct instrument lacks one named observation
required by the decision. Before authoring it, cap harness implementation and
repair separately from product measurement; by default allow one initial
implementation, one repair cycle, and no more harness time than one planned
measurement run. A second harness/probe defect, lost artifact, schema or
lifecycle hardening demand, or exhausted harness budget before any product
sample ends that instrument. Switch to a simpler observation or report the
exact capability gap. Only a `critical` profile with a named irreversible risk
may justify a larger harness budget.

Control only variables capable of crossing the decision threshold. For
exploratory or reporting latency, label manageable contention or provenance
uncertainty instead of turning the probe into release software with socket,
process-lifecycle, package-lineage, or environment-purity proof. A disposable
harness receives independent review only when its result itself authorizes a
consequential action.

## Handle bugs once

Reproduce once, minimize only enough to assign the failing layer, fix, run the
reproducer or regression once, then stop. Classify an observation as product,
input, harness-or-probe, environment, provenance, cache-bootstrap, or
external-wait. Treat non-product observations as diagnostic until isolated;
preserve the result rather than retrying it into proof.

## Batch and supervise

Reason through all independent edits before paying for an expensive check.
Serialize only when a later edit depends on an earlier result. Mine one slow
failure for its full inventory, group symptoms by cause, repair the causes, and
run the named check once more only when failure left the decision open. Report
the number of slow verification runs.

Give every bounded check one supervisor, phase or case deadlines, and a visible
progress point. The supervisor owns and reaps every child. On failure or silence
past the bound, stop the affected process, preserve its output and artifacts,
and classify the failure before choosing another action. Remote CI confirms
asynchronously; do not wait on it to land local work.

## Reject verification theatre

Reject these recognizable failure modes:

- **Full-suite reflex:** running everything because the edit is small or local.
- **Oracle inflation:** inventing more authorities after the named evidence
  already decides the claim.
- **Immutable-manifest or seal ceremony:** adding provenance machinery that
  cannot change the decision.
- **Hermeticity worship:** isolating dependencies beyond what the verdict needs.
- **Compatibility archaeology and tombstone preservation:** retaining obsolete
  behavior without an explicit compatibility requirement.
- **Retry-as-proof:** turning a failed or flaky gate green by rerunning it.
- **Post-pass reassurance loops:** checking again after the required pass.
- **Mega-journey:** making one journey conflate unrelated claims.
- **Remote-CI waiting:** serializing a local landing on external confirmation.
- **Timeout inflation:** lengthening a bound without evidence that legitimate
  work changed.
- **Harness construction for a reversible tiny edit:** building verification
  infrastructure costlier than the decision at risk.
- **Checking after the decision is already made:** collecting evidence that can
  no longer change the action.

Hermeticity, manifests, compatibility layers, broader suites, and new harnesses
are tools, not virtues. Use one only when its absence would change the selected
profile's decision.
