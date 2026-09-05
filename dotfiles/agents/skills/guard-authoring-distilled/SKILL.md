---
name: guard-authoring-distilled
description: >-
  Implement or change a command/write guard and its shared identity, activity gate, provider wiring, and deny/pass fixtures.
---

# Guard authoring

A refusing guard has one `PreToolUse` identity shared by its implementation,
catalog, provider wiring, worker chains, and fixtures. Telemetry and lifecycle
hooks retain their actual events.

- Edit the resolved owner in a worktree, never a projection.
- Drain stdin, bound input near 1 MiB, and fail open on malformed/oversized
  input, missing optional runtime, unresolved paths, or internal errors.
- Honor `AGENT_NO_AUTHORING_HOOKS`. Otherwise require one exact active
  `kind=hook` row in North's valid generation; missing, duplicate, invalid,
  or inactive state disables the guard.
- Deny only a decoded dangerous operation and name a sanctioned alternative.
  Prefer stdout JSON with exit zero; exit 2 plus one stderr reason is supported.
  Ask only for a real operator decision.

Resolve the ID with `agents inspect` and `agents path`. Wire only events and
tool payloads the implementation actually decodes. Exercise dangerous,
sanctioned, adjacent, malformed, unavailable-state, and override cases through
every affected provider or worker chain.

Run the nearest affected checks once. Missing owner or decoder evidence blocks
that wiring; prose or a second identity cannot fill the gap.
For payloads, envelopes, and wiring, use `agents path guard-authoring-reference`.
