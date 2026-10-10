---
name: repo-safety
description: >-
  Edit and publish ~/code repositories through owned worktrees, enumerated staging, and safe-push; preserve main checkouts, pins, and peer work.
grounded: 2026-10-09
written: 2026-10-09
---

# Repository safety

- Edit `~/code/<project>/worktrees/<slug>` and preserve main/pins; use [notes](references/notes.md) for creation, rescue and retirement.
- Keep build output inside its worktree, including Rust target directories, or one explicit temporary target.
- Keep ISO/disc images and proprietary extracted game files outside Git trees in private storage; publish only permitted authored tools/numerical facts.
- Stage named paths, finish commit hooks, publish separately through `safe-push --to main` and fast-forward clean main.
- Run the project's dependency install (`bun install` for smashcraft/wisp) in a new worktree before its first safe-push; its pre-push checks fail without it.
- Retire a worktree only as its owner/accountable parent after its work settles; preserve unknown ownership and live consumers.
- Signal owned processes by exact PID or unique scoped pattern.
- Resolve guard denials through the sanctioned route and preserve secret/private-data/destructive/live-consumer boundaries.
