# Worker incident lifecycle fixtures

## Positive durable-feedback case

An admitted worker starts, then passes its supervisor window without liveness
or valid terminal reporting. The supervisor preserves admission, last
activity, liveness, control, and reporting evidence; computes the stable
signature; and creates one `IncidentSeed`. A second complete-signature
observation increments that seed instead of creating another.

Only that worker seam is quarantined. A replacement or already-authorized
bounded fallback keeps delivery moving while one priced reproduction tests
falsifiable hypotheses.
The exact upstream owner repairs the cause, the focused regression passes, the
repair is activated, preferred topology is restored, and the repaired primary
path canary observes healthy startup, liveness, control, and terminal reporting.
North records any agent-run restoration-debt exit evidence; only then
may incident closure be considered.

If fallback delivery finishes first, delivery is complete while the incident
and restoration debt remain open.

## Positive retry-deduplication case

A retry changes only the excluded actor/run identity and timestamp. Every
canonical signature field remains unchanged: lifecycle class, stable affected
actor or sender role, intended operation, emitted recipient/tool, normalized
argument shape, runtime/provider mode, error class, and stable affected
worker-startup seam. It increments the existing seed's observation count and
evidence; the excluded run-specific differences do not create another seed.

## Negative cross-seam collision case

Two failures share lifecycle class, intended operation, normalized call shape,
runtime mode, and error class, but one affects worker admission while the other
affects terminal reporting. Their stable affected seams differ, so they produce
two signatures and two seeds. A multi-seam observation is deterministically
split on those scopes rather than collapsed into one incident.

## Reopen rejects stale evidence

A closed generation recurs with the same complete signature. Reopening
increments the generation and leaves the old repair, regression, activation,
primary-canary, and restoration-debt exit evidence as historical only. The
reopened incident cannot close from that evidence: its new generation must be
contained, investigated, classified, owned, repaired, regressed, activated,
and primary-canaried before closure is considered.

## Reporting delivery case

`/root/clause_v0_program_commander` emits an opaque token payload where root
expects a consumable plaintext status card. Normalize the complete canonical
tuple as:

- lifecycle class: `reporting`;
- stable affected actor or sender role: `/root/clause_v0_program_commander`;
- intended operation or report boundary: `commander-to-root plaintext-status-card`;
- emitted recipient/tool or payload surface: `agent-report/message-body`;
- normalized argument or payload signature: `opaque-token:gAAAA`;
- runtime/provider mode: `native-collaboration`;
- normalized error class: `opaque-report-payload`; and
- stable affected seam/surface scope: `commander-terminal-reporting`.

The intended report boundary and emitted message-body surface are distinct.
Retain only the normalized `opaque-token:gAAAA` signature and never the token
body. Those fields create one `reporting` `IncidentSeed`, and a repeat with the
same tuple increments it.

After North has typed proof that no provider side effect became observable,
`agent-run-lifecycle-distilled` admits one plaintext-resend fallback and delivery
remains active. Record its North-owned requested/resolved route and
restoration-debt fields in the same incident seed. The resend, delivery state,
and open debt do not create a second lifecycle or close reliability.

## Episodic-negative control

A healthy worker remains inside its admitted supervisor window, terminates
through expected cancellation with complete reporting, or receives an
explained policy rejection. These observations do not prove an unexplained
death or silence and do not create duplicate incidents.

Do not quarantine adjacent workers, create one seed per retry or observer,
merge distinct affected seams, promote fallback to the new default, treat
fallback success as the primary canary, or close reliability because the
product artifact was delivered.
