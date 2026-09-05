# Remote agents and account pools

## Runtime and account access

The existing CLI is `/home/tom/.local/bin/codex` on the server. Verify the
current version and subscription authentication without reading auth files:

```sh
ssh -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes \
  -i /home/tom/.ssh/greywrought-wiki-admin tom@137.184.38.104 \
  '/home/tom/.local/bin/codex login status'
```

Use the requested model and reasoning effort explicitly, verify their remote
availability, and preserve existing subscription sign-in. Reuse or securely
transfer existing subscription access when the requested task requires it,
under the global credential-use boundary; do not introduce provider API-key
billing. Inspect the installed
CLI help before constructing a launch command. Worktree and executable paths
differ from the laptop; resolve them on the host rather than transplanting
local paths or assuming Bun/Cargo are on the remote user's PATH.

## Pool enrollment versus remote control

Remote Control sign-in and codex-lb account enrollment are separate. A paired
phone does not prove that the balancer contains any accounts or receives model
requests. Inspect both inventories before asking for another sign-in. When
the task requests the existing pool on this verified Droplet, use codex-lb's
supported account export/import over SSH into its encrypted store; never print
the export or create a plaintext credential file. Preserve the phone-control
login and existing remote accounts. Do not ask for an additional transfer
confirmation or re-enroll accounts that already have usable credentials.

After transfer, verify source-account coverage, remote eligibility, and actual
requests from the intended session. Quota-exhausted accounts remain enrolled
but cannot serve until quota recovers. Do not claim every account serves every
request: routing may retain affinity and must respect eligibility. Check
credential-refresh behavior when both hosts will remain active; do not silently
replace an independent server with a tunnel dependent on the laptop.

Follow the available run-design, ownership, and supervision procedures for
delegation. Save the scoped plan and restart-grade status on the host. Require
the actual run's ownership acceptance and first useful activity before reporting
that work started. A systemd unit, PID, or background log alone is insufficient.
Use the established detached-session mechanism for an explicitly requested
remote continuation, and retain its session ID, service identity, status path,
and exact stop/resume procedure.

This server also serves the public game. Bound development CPU and memory and
keep test servers private; do not starve or restart production for a build.
The live Greywrought release selector is `/srv/greywrought/current`. Inspect it
read-only when needed; never edit the selected release in place. Development
launch does not authorize changing this selector or deploying a new release.

## Evidence and boundaries

A spawned process proves launch mechanics, not accepted work or useful activity.
A visible remote thread proves listing, not that a phone displayed it. Credential
enrollment proves possession, not current quota eligibility. Report the exact
observed boundary and preserve the public game's resource budget independently.
