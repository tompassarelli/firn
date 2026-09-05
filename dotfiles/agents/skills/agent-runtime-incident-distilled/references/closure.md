# Repair and closure

## Incident versus run settlement

This skill alone owns incident lifecycle transitions and the reliability
closure decision. `agent-run-lifecycle-distilled` owns concrete fallback,
restoration, and terminal agent-run settlement. Record its route and
restoration-debt facts as incident evidence without creating a second debt
model, broadening fallback authority, or changing the default. Fallback
completion may close delivery containment but not the incident.

## Current-generation state transitions

Use explicit states:
`seeded → contained → investigated → classified → owned → repaired → regressed
→ activated → primary-canaried → closed`. `reproduction-blocked` and
`reopened` remain open. Do not skip a state without its named evidence.

When a closed signature recurs, increment `generation`, enter `reopened`, and
retain prior evidence as history tagged with its old generation. Old repair,
regression, activation, primary-canary, and restoration-debt exit evidence is
stale for the new generation and cannot satisfy closure. From `reopened`, make
a fresh transition through containment, investigation, classification,
ownership, repair, regression, activation, and primary canary before closing;
do not close directly from `reopened` or reuse old-generation evidence.

For a reproduced Codex defect repaired in a downstream fork, prepare a
sanitized upstream report. Publish an issue only when external reporting is
within the authorized task, including the minimal reproduction, affected
version, expected and actual behavior, and the downstream solution outline.
Record its URL, the downstream repair commit, and the exact upstream release or
commit that retires the fork patch. Do not publish credentials, private
transcript content, or a pull request. Record any required but pending external
report separately. Do not treat an
unrequested publication as a prerequisite to independent delivery or infer
permission to speak for the operator.

Close only when the upstream repair is landed, the focused regression passes,
the repaired authority is activated, the preferred topology is restored, and
a primary-path canary exercises the triggering lifecycle seam successfully,
all in the current generation. When current-generation fallback restoration
debt exists, also require its North-owned exit evidence. Fallback-path
success is not a primary canary.

## Why old evidence expires

A recurrence is a counterexample to the earlier repair claim. Retaining history
helps diagnosis, but that history cannot prove the current generation repaired.
The primary-path check must exercise the triggering seam, not merely show that
another provider or topology can finish the work.
