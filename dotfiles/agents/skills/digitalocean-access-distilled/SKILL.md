---
name: digitalocean-access-distilled
description: >-
  Access Tom's existing DigitalOcean account and Droplets, resolve the verified
  SSH route, and start or inspect remote development runs. Use for DigitalOcean
  account access, greywrought-dev, remote Codex execution, and Droplet operations;
  this skill does not itself authorize provisioning, billing, or deployment.
---

# DigitalOcean access

Distinguish account control from access to an existing server. SSH does not
prove DigitalOcean API access, account identity, or permission to change billing.

## Existing Greywrought server

The verified server is `greywrought-dev`, at `137.184.38.104`. From Tom's local
machine, use the existing SSH identity without reading its contents:

```sh
ssh -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes \
  -o ConnectTimeout=10 -i /home/tom/.ssh/greywrought-wiki-admin \
  root@137.184.38.104 'hostname; id'
```

Use root only for the required administrative boundary; run agent development
as the established `tom` user. The local SSH alias `greywrought-dev` is not
currently configured. `play.greywrought.com` is Cloudflare-proxied and must not
be used as an SSH destination. The historical `165.232.138.122` route is not
the current verified server; do not cycle through historical addresses.

Host keys must match the existing known-hosts record. A mismatch stops access;
do not disable host checking or replace the key based only on an unauthenticated
scan. If the verified address becomes unreachable, consult authenticated
account inventory or the newest successful access record through `convo`.
Verify hostname and the requested service before a write.

## Account control

The account console is https://cloud.digitalocean.com/. Use an existing
authenticated browser session or an already configured `doctl` context. This
machine currently has no verified `doctl` executable or configured context;
do not claim API access from working SSH.

When a request requires account inventory or API actions, inspect command
availability and credential-file existence only. If an established context is
available, `doctl account get` and a narrowly selected Droplet listing can
verify its identity without printing credentials. Otherwise stop that API seam
and ask the operator to establish the approved account access. Do not create a
personal access token, copy browser cookies, scrape password stores, or move
credentials between machines as an access workaround.

Creating, resizing, destroying, changing firewalls/DNS, adding billable
resources, or changing production requires authorization for that specific
outcome. A request to run development on the account ordinarily means reuse
the existing server, not provision a new one.

## Remote agent work

The existing CLI is `/home/tom/.local/bin/codex` on the server. Verify the
current version and subscription authentication without reading auth files:

```sh
ssh -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes \
  -i /home/tom/.ssh/greywrought-wiki-admin root@137.184.38.104 \
  'runuser -u tom -- /home/tom/.local/bin/codex login status'
```

Use the requested model and reasoning effort explicitly, verify their remote
availability, and preserve existing subscription sign-in. Never copy local
Codex credentials or introduce provider API-key billing. Inspect the installed
CLI help before constructing a launch command. Worktree and executable paths
differ from the laptop; resolve them on the host rather than transplanting
local paths or assuming Bun/Cargo are on the remote user's PATH.

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
