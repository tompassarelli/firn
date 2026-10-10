---
name: repo-safety
description: >-
  Edit and publish ~/code repositories through owned worktrees, enumerated staging, and safe-push; preserve main checkouts, pins, and peer work.
grounded: 2026-10-09
written: 2026-10-09
metadata:
  kind: playbook
---

# Repository safety

- Edit `~/code/<project>/worktrees/<slug>` and preserve main/pins; use [notes](references/notes.md) for creation, rescue and retirement.
- Keep build output inside its worktree, including Rust target directories, or one explicit temporary target.
- Keep ISO/disc images and proprietary extracted game files outside Git trees in private storage; publish only permitted authored tools/numerical facts.
- Stage named paths, finish commit hooks, publish separately through `safe-push --to main` and fast-forward clean main; chain a landing after its check with `&&`, never `;`.
- Retire a worktree only as its owner/accountable parent after its work settles; preserve unknown ownership and live consumers.
- Before starting an issue, check `lane-gc --unlanded` for an existing branch referencing it and continue that instead of starting over; an owner who abandons a lane deletes it in the same turn. The hourly `lane-gc` timer retires landed, clean, idle lanes.
- Signal owned processes by exact PID or unique scoped pattern.
- Resolve guard denials through the sanctioned route and preserve secret/private-data/destructive/live-consumer boundaries.
