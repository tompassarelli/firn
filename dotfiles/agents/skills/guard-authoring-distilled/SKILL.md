---
name: guard-authoring-distilled
description: >-
  Use whenever adding, changing, wiring, or debugging an enforcement hook on
  this machine: blocking a command or write, warning before a tool call, or
  making the same guard reach Codex and North workers. Covers singular North
  identity/activity, the deny protocol, every decoded tool entrance, fail-open
  behavior, the activity kill switch, and two-direction fixtures.
---

# Guard authoring, distilled

A refusing guard is one `PreToolUse` identity whose implementation, North
catalog row, provider wiring, worker chain, activity gate, and focused fixture
agree. Telemetry and lifecycle hooks retain their real events.

## Hard boundaries

- Edit only the exact owner source in a worktree. Never edit projections,
  provider materializations, generated `.nix`, pins, or immutable generations.
- Drain stdin before deciding, bound input near 1 MiB, and fail open on malformed
  or oversized input, optional-runtime failure, unresolvable paths, or internal
  errors.
- Preserve `AGENT_NO_AUTHORING_HOOKS` as a per-session off switch. With it
  unset, enable only an exact active `kind=hook` row from North's current valid
  generation; missing, duplicate, malformed, or inactive state disables.
- Deny the precise dangerous shape and name a legal next action. Prefer the
  stdout JSON deny protocol with exit zero; exit 2 plus one stderr reason is the
  alternate protocol. Use `ask` only for a genuine operator decision.
- Match only entrances the implementation decodes from real payloads. Do not
  list a tool for apparent coverage, and do not leave a denial without its
  recommended passing route.

## Minimum workflow

1. Locate one globally unique hook ID and its exact owner with `agents inspect`
   and `agents path`.
2. Implement bounded input, the activity gate, exact decoder coverage, and the
   deny protocol at the owner source.
3. Wire that same identity to the real Codex event and every North worker chain
   whose payload it decodes.
4. Keep one focused two-direction fixture: all supported dangerous entrances
   deny, sanctioned and adjacent forms pass, unavailable state follows the
   declared fail-open behavior, and activity/override switches are exact.
5. Run each smallest affected owner, provider, and worker-chain check once.

Stop if any required provider/worker source cannot resolve or if a matcher has
no native decoder evidence. Never fill the gap by copying behavior into prose
or inventing a second hook identity.

Exact payload and fixture details live in the reference skill; load it only for
an explicit request or a named unresolved detail, per the always-loaded policy.
