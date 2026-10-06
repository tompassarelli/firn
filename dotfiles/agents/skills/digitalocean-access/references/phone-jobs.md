# Phone-visible jobs

## Choose a visible execution source

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

## Effective permissions, not role prose

Native child spawning inherits its parent's live permission profile despite a
custom role's sandbox setting. Resolve this before admitting implementation:
a read-only parent cannot promise writable native children. Check the child's
`canAcceptDirectInput` before assuming app-server turn controls can independently
configure it; the current native children report false. A role prompt alone
grants no effective write access. Preserve the stock coordinator's read-only
boundary unless the user explicitly overrides it. When the user explicitly
requests full executive permissions for the team, apply `dangerFullAccess`
with approval policy `never` to the actual parent turn, record that per-run
authority exception, and verify a newly admitted worker inherits it. This does
not authorize production, credentials, or unrelated destructive operations.

## Rationale and version limits

The source filtering and permission behavior above are observations of named
installed versions. Recheck the current protocol before applying them to a
new version. A role description cannot override the actual parent permission
profile, and pairing does not establish account-pool enrollment.
