---
name: verification
description: >-
  Select, run, supervise, and interpret proportionate evidence. Use for tests,
  checks, debugging reproductions, bug validation, CI, release preflight,
  performance measurements, or any claim that work is proved, passing, fixed,
  stable, or ready to publish.
---

# Verification

Choose a profile before running a check. State the claim and what pass or fail
changes. If both outcomes lead to the same action, do not run it. Stop as soon
as the named decision is made.

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
For a performance claim, define the metric and decision threshold first and
isolate contention that could falsify the measurement.

## Handle bugs once

Reproduce once, minimize only enough to assign the failing layer, fix, run the
reproducer or regression once, then stop. Treat timing, infrastructure,
environment, and probe failures as diagnostic until isolated; they are not
product verdicts. Preserve the diagnostic result rather than retrying it into
proof.

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
