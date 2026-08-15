# Claude system docs — start here

The map of how Claude Code is set up on this machine, split by **concern** and
**rot-rate** so each piece is maintained the right way. Read top to bottom, or jump.

| # | doc | layer | rots | maintained by |
|---|---|---|---|---|
| 1 | [01-canonical.md](01-canonical.md) | how Claude Code works + the levers + when to use each | slowly (Anthropic contracts) | hand |
| 2 | [02-local-map.md](02-local-map.md) | how THIS system is wired right now | every config change | **generated** |
| 3 | [03-north.md](03-north.md) | where the north/claim substrate plugs in | occasionally | hand |

- **① canonical** — the stable model. What Claude Code *is*, the 80/20 levers
  (CLAUDE.md / settings / hooks / skills / MCP / plugins / subagents), and the
  hooks-vs-skills-vs-CLAUDE.md decision. Update only when the harness changes.
- **② local map** — **NEVER hand-edit.** Run `firn repo architecture` (walks disk +
  settings + plugin manifests). A diff here means the system actually moved.
- **③ north** — the substrate Claude points at, and the SDK dispatch model
  that coordinates agent work via thread-driven posture.

## Reading the whole thing top-to-bottom

```bash
firn repo architecture bundle   # canonical + current local map + north, concatenated
firn repo architecture          # regenerate + print the local map (02)
```

Why split: a single hand-maintained mega-doc rots because it mixes stable
contracts (slow) with live wiring (fast). The fast layer is generated; the slow
layers are small and conceptual. The bundle stitches them on demand — no
duplicated, drifting copy.
