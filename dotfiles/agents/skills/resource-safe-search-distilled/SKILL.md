---
name: resource-safe-search-distilled
description: >-
  Select bounded filesystem roots before searching repository containers or virtual filesystems; use native process metadata for process discovery.
---

# Resource-safe search

Search one exact checkout, subtree, file, or bounded data root. A container
holding main, worktrees, or pins is not a search root. This includes
`rg --files` and an implicit working-directory root.

Pass an absolute checkout/subtree operand in container layouts; launch context
may differ from the tool's working directory. For pipeline filtering, name
stdin explicitly: `producer | rg PATTERN -`.

Select a process with bounded native metadata, then inspect one required field
or edge, such as `readlink -e /proc/PID/cwd`. Never recursively or
shell-glob search `/proc`, `/sys`, `/dev`, or `/run`. Resolve a process cwd
before searching its ordinary filesystem contents. Narrow ambiguous selection
by PID, command, unit, or user.

Use `convo-distilled` for transcript searches. For a demonstrated unsafe search,
amend this owning rule and guard, remove duplicates, and check the offending
shape plus the nearest legitimate bounded operation before activation.
