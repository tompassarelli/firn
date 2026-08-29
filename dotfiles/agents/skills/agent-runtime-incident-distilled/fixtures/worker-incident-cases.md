# Worker incident lifecycle fixtures

## Positive durable-feedback case

An admitted worker starts, then passes its supervisor window without liveness
or valid terminal reporting. The supervisor preserves admission, last
activity, liveness, control, and reporting evidence; computes the stable
signature; and creates one `IncidentSeed`. A second complete-signature
observation increments that seed instead of creating another.

Only that worker seam is quarantined. A replacement or bounded fallback keeps
delivery moving while one priced reproduction tests falsifiable hypotheses.
The exact upstream owner repairs the cause, the focused regression passes, the
repair is activated, preferred topology is restored, and the repaired primary
path canary observes healthy startup, liveness, control, and terminal reporting.
Only then may restoration debt and the incident close.

If fallback delivery finishes first, delivery is complete while the incident
and restoration debt remain open.

## Episodic-negative control

A healthy worker remains inside its admitted supervisor window, terminates
through expected cancellation with complete reporting, or receives an
explained policy rejection. These observations do not prove an unexplained
death or silence and do not create duplicate incidents.

Do not quarantine adjacent workers, create one seed per retry or observer,
promote fallback to the new default, treat fallback success as the primary
canary, or close reliability because the product artifact was delivered.
