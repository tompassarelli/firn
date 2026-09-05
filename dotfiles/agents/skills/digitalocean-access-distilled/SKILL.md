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
  tom@137.184.38.104 'hostname; id'
```

Direct SSH as `tom` is verified. Use `root` with the same identity only for a
required administrative boundary. The local SSH alias `greywrought-dev` is not
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
  -i /home/tom/.ssh/greywrought-wiki-admin tom@137.184.38.104 \
  '/home/tom/.local/bin/codex login status'
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

## Phone-visible jobs

When phone monitoring is required, use the existing Remote Control app-server,
not a detached `codex exec` process. Codex 0.153.4's default `thread/list` hides
`exec` sources even when running; a persistent goal or a resumed exec thread
does not establish visibility. A native app-server thread/fork has the normal
app source. Before a handoff, settle the old run's children and pause only its
automatic continuation; transfer full history and acknowledged ownership,
never run both copies or edit Codex's databases to change source metadata.

`codex app-server daemon version` reports the managed server and socket.
The verified private socket is
~/.codex/app-server-control/app-server-control.sock on greywrought-dev. Use an
SSH-forwarded WebSocket with the supported initialize/initialized handshake;
`codex app-server proxy` proxies raw WebSocket bytes, not JSON lines. Keep all
listeners private. Generate protocol schemas from the installed CLI when
needed, rather than guessing API shapes.

Read `remoteControl/status/read` and `remoteControl/client/list` to verify a
connected environment and existing iPhone pairing. The environment was
env_e_6a984dd0cf248332ac329fd0248370ad when verified; re-read its live identity.
Do not regenerate pairing if the device is already paired. If pairing is
actually required, use `codex remote-control pair` and the user's app flow;
do not move credentials. Confirm the exact job appears in default `thread/list`
with active status, actual requested model/effort, and useful execution before
reporting launch. Distinguish server-side visibility from observing the phone
screen. Phone route: ChatGPT → Remote → greywrought-dev → named job.

The stock coordinator remains read-only. Native child spawning inherits its
parent's live permission profile despite a custom role's sandbox setting.
The runtime host must separately admit the terminal child's exact writable
lane through supported per-thread controls; a role prompt alone grants no
effective write access. Never broaden coordinator permissions to resolve it.

## Ubuntu sandbox prerequisite

On this Ubuntu 24.04 host, missing distribution bubblewrap caused
`bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted`. The owning
repair was the Ubuntu `bubblewrap` and `apparmor-profiles` packages, followed
by installing Ubuntu's
/usr/share/apparmor/extra-profiles/bwrap-userns-restrict at
/etc/apparmor.d/bwrap-userns-restrict and loading that exact profile with
`apparmor_parser -r`. The global
`kernel.apparmor_restrict_unprivileged_userns=1` remains enabled. Verify an
actual sandboxed command through the intended app-server after repair; do not
disable AppArmor globally or bypass Codex sandboxing.
