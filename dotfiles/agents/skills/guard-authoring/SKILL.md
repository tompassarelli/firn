---
name: guard-authoring
category: agents
description: >-
  Use whenever adding, changing, wiring, or debugging an enforcement hook on
  this machine: blocking a command or write, warning before a tool call, or
  making the same guard reach Codex and North workers. Covers singular North
  identity/activity, the deny protocol, every decoded tool entrance, fail-open
  behavior, the activity kill switch, and two-direction fixtures.
---

# Authoring a guard on this machine

A refusing guard runs at `PreToolUse`; telemetry and lifecycle hooks use their
real events and must not masquerade as guards. One hook is complete only when
its implementation, global North catalog identity, provider wiring, worker
chain, activity gate, and focused behavior fixture agree.

Paths below use `repo:path`. Edit only an owner worktree, never `main`, a pin,
`~/.agents`, `~/.codex`, `/etc/codex`, or an immutable North generation.

## Locate the one identity

Use one globally unique hook ID declared by one of the exact sources in
`north:agent-catalog/sources.json`. Its catalog owner is the exact source
`repo:path`; no forwarding source or provider alias survives. Declare support
relations and distributions in the owning source and operator overlay. North alone resolves permission, active
claimants, module closure, provenance, and provider activation paths into
`${NORTH_AGENT_STATE_ROOT:-~/.local/state/north/agents}/current/activation.json`.

Most owner scripts live under `north:profiles/tom/hooks`. A Firn-owned native
policy instead points exactly at NixOS source and the installed native
executable. `firn-system-policy` is the reference: North's shell adapter is a
provider distribution of that identity, never another hook or authority.

`agents status`, `inspect`, `path`, `on`, and `off` are thin clients of this
authority. A hook that is absent from the catalog is absent; a permission-off
or claimant-off hook remains catalogued and reports why it is inactive.

## Write the implementation

Drain stdin completely before deciding. Bound input near 1 MiB and fail open
on overflow, malformed JSON, a missing optional runtime, an unresolvable path,
or any internal error. Silence with exit zero is the common allow path.

Retain the per-session override:

```bash
case "${AGENT_NO_AUTHORING_HOOKS:-}" in
  ''|0|false) ;;
  *) exit 0 ;;
esac
```

When the override is unset, read the hook's exact `kind=hook`, `id`, and
resolved `active` boolean from the current North activation generation. A
missing, duplicate, malformed, wrong-schema, or inactive row disables the
hook. Never re-resolve modules or claims in the provider adapter.

### Deny protocol

Prefer stdout JSON with exit zero:

```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"<legal next action>"}}
```

Exit 2 with one stderr reason is also understood. The reason must name the
compliant path forward. `ask` is valid when the decision genuinely belongs to
the operator.

## Cover every entrance the decoder actually supports

Equivalent effects may arrive through `Edit`, `Write`, `MultiEdit`, Bash, or a
provider-specific patch tool. Matchers and decoder evidence must agree:

- `Edit`, `Write`, and `MultiEdit` normally carry `tool_input.file_path` (some
  providers use `filePath`).
- Bash carries `tool_input.command` and can reproduce file edits through
  redirects, scripts, Git, or text tools.
- Codex `apply_patch` carries a patch envelope, not necessarily one decoded
  path. Include it only when the implementation deliberately parses its real
  payload and resolves relative paths against `cwd`.

Never list a tool merely to look complete. If native decoder evidence shows a
tool cannot be interpreted, omit that hook from the corresponding matcher and
keep a fixture proving the omission. Another guard may independently support
that entrance; for example, the launch-critical worktree guard decodes
`apply_patch`, while `firn-system-policy` deliberately matches only
`Edit|Write|MultiEdit` plus Bash.

Refuse the precise dangerous shape, not adjacent legitimate work. A denial
must not trap an actor without the alternative it recommends.

## Wire Codex

Codex trusts `/etc/codex/requirements.toml` with
`allow_managed_hooks_only = true` and `managed_hook_failure_mode = "block"`.
For a promoted shell hook, add the exact command under its supported anchored
matcher and declare the promoted source in
`nixos-config:modules/codex/default.bnix`. North must also include it in its
sealed enforcement source contract. Provider adapters instead remain
materialized in North's current generation and Firn declares only stable
`/etc/codex/hooks/<adapter-id>` links to those payloads.

The command shape is:

```text
/etc/codex/hooks/runtime/env -u BASH_ENV -u ENV /etc/codex/hooks/runtime/bash /etc/codex/hooks/<id>.sh
```

Firn's Beagle/JS policy is promoted with the Firn CLI runtime and binds as
`~/.local/lib/firn/cli/current/bin/firn-system-policy`. Refresh that runtime
from committed source with `firn-runtime-update`; it does not belong to the
NixOS system closure.

Provider lifecycle wrappers are separate. Register each spawn, tool-use,
delegated, stop, and terminal source under its exact hook identity and bind its
wrapper to the actual Codex event. Those wrappers read North activity and
preserve stdin; they are not fake `PreToolUse` enforcement.

## Wire North workers

Add the exact catalog ID/source to every worker chain whose payload the
implementation decodes. A Bash guard normally reaches both orchestration-
allowed and plain-worker Bash chains. Edit-family support reaches the edit
chain; patch support needs its own proven decoder path. North must fail if a
catalogued required hook cannot resolve rather than silently dropping it.

Exercise the composed worker callback with real `{tool_name, tool_input, cwd}`
payloads. Listing a source without invoking the chain is not evidence.

## Verify both directions

Keep the focused fixture beside the implementation or provider adapter. It
must assert:

- every supported bad entrance denies;
- the named sanctioned alternative passes;
- nearby text, quoted mentions, and scoped forms pass;
- malformed, oversized, and unavailable-state inputs behave as declared;
- permission/activity off suppresses the hook;
- per-session force-live/off behavior is exact;
- Codex and North composed paths invoke the same identity.

For Firn-owned native policy, additionally prove no hosted runtime, native
decoder behavior for `Edit`, `Write`, `MultiEdit`, and Bash, and intentional
`apply_patch` matcher omission. For lifecycle wrappers, exercise all five
adapters against one activation fixture and prove inactive/missing/invalid
generations delegate nowhere while draining stdin.

Run the smallest affected checks once: the owner fixture, the provider wiring
fixture, and the relevant North chain fixture. After publication and any
required rebuild/promotion, `agents inspect <id>` must show the exact owner,
support provenance, resolved activity, and activation paths.
