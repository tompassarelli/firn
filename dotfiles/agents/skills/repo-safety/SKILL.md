---
name: repo-safety
description: >-
  Edit and publish ~/code repositories through owned worktrees, enumerated staging, and safe-push; preserve main checkouts, pins, and peer work.
---

# Repository safety

- Edit `~/code/<project>/worktrees/<slug>` and preserve main/pins; use [notes](references/notes.md) for creation, rescue and retirement.
- Keep build output inside its worktree, including Rust target directories, or one explicit temporary target.
- Keep ISO/disc images and proprietary extracted game files outside Git trees in private storage; publish only permitted authored tools/numerical facts.
- Stage named paths, finish commit hooks, publish separately through `safe-push --to main` and fast-forward clean main.
- Retire a worktree only as its owner/accountable parent after its work settles; preserve unknown ownership and live consumers.
- Signal owned processes by exact PID or unique scoped pattern.
- Resolve guard denials through the sanctioned route and preserve secret/private-data/destructive/live-consumer boundaries.
