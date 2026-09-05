---
name: guard-authoring-reference
description: >-
  Full guard notes for identity/activity, deny envelopes, decoded entrances, provider wiring, and fixtures.
---

# Guard authoring: full notes

## Enforcement is a separate layer

A skill explains the sanctioned workflow; the guard enforces a deterministic
boundary even when that skill is not loaded. A provider wrapper transports the
real event and payload. Neither should independently invent identity,
permission, module closure, or source authority.

Choose fail-open behavior for unavailable ancillary authoring state as the
owning contract requires; never silently redefine a security enforcement
contract. A deny must point to a legal next move, not merely scold.

## Identity and activity inputs

Resolve the owner with `agents inspect <id>` and its current catalog; do not
copy a historical hooks-directory path. A Firn-owned native policy points at
its NixOS source and installed executable. `firn-system-policy` illustrates
that shape; a provider adapter is a distribution, not a second identity.

The current generation defaults to
`${NORTH_AGENT_STATE_ROOT:-~/.local/state/north/agents}/current/activation.json`.
Read one exact row by `kind`, `id`, and resolved `active` boolean. North has
already resolved permission, claimants, module closure, and provenance.

The session switch shape is:

```bash
case "${AGENT_NO_AUTHORING_HOOKS:-}" in
  ''|0|false) ;;
  *) exit 0 ;;
esac
```

## Deny envelope

The preferred stdout response is:

```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"<legal next action>"}}
```

Exit 2 with one stderr reason is the supported alternate.

## Decoded entrances

| Tool family | Payload to decode |
| --- | --- |
| `Edit`, `Write`, `MultiEdit` | `tool_input.file_path`, with `filePath` where the provider uses it |
| Bash | `tool_input.command`, including indirect writes through scripts, Git, redirects, or text tools |
| Codex `apply_patch` | patch envelope plus relative-path resolution against `cwd` |

Include `apply_patch` only when the native implementation deliberately parses
that envelope. For example, the launch-critical worktree guard decodes it;
`firn-system-policy` deliberately covers the edit family and Bash instead.

## Provider wiring

Codex uses managed hooks from `/etc/codex/requirements.toml`. A promoted shell
hook command has this shape:

```text
/etc/codex/hooks/runtime/env -u BASH_ENV -u ENV /etc/codex/hooks/runtime/bash /etc/codex/hooks/<id>.sh
```

Declare promoted sources in `nixos-config:modules/codex/default.bnix`, include
them in North's sealed enforcement-source contract, and regenerate through
`firn repo build`. Stable Firn native policy binds directly as
`/run/current-system/sw/bin/firn-system-policy`. Provider lifecycle wrappers
instead bind to their actual spawn, tool-use, delegated, stop, or terminal
events and preserve stdin.

For North workers, add the exact catalog ID/source to each chain whose payload
is decoded. Exercise the composed callback with real
`{tool_name, tool_input, cwd}` input; source listing alone is not invocation
evidence.

## Fixture matrix

Cover every supported dangerous entrance and its named sanctioned alternative,
plus nearby text, quoted mentions, and scoped passing forms. Include malformed,
oversized, and unavailable-state input; permission/activity off; and exact
session force-live/off behavior. Exercise Codex and North paths against the
same identity.

Firn native-policy fixtures additionally cover hosted-runtime independence,
the edit-family and Bash decoders, and intentional `apply_patch` omission.
Lifecycle-wrapper fixtures exercise all five adapters and show that inactive,
missing, or invalid generations drain stdin and delegate nowhere.

After publication and any required promotion, use `agents inspect <id>` to
confirm exact owner, support provenance, resolved activity, and activation
paths.

## Why two-direction fixtures matter

A dangerous command refusal alone cannot show the sanctioned route remains
usable. Pair each refusal with its permitted neighbor, including quoted text
that only mentions the operation. Exercise the decoded payload and composed
callback; a file appearing in a source list is not proof it ran.
