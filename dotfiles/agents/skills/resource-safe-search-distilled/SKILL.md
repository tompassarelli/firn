---
name: resource-safe-search-distilled
description: >-
  Choose bounded roots for rg-like content and file-enumeration search, and
  diagnose process state without traversing kernel or runtime virtual
  filesystems. Use before searching a repository container, /proc, /sys, /dev,
  or /run, or when refining policy after a demonstrated unsafe search. Ordinary
  search inside one exact checkout or subtree does not need this skill.
---

# Resource-safe search

Keep `rg` and similar recursive content or file-enumeration tools inside one
exact checkout, subtree, file, or bounded data root. A repository container
holding `main/` plus `worktrees/` is not a search root: select one checkout or
subtree first. This applies equally to an explicit operand and to the current
directory supplying the default `.` root, including `rg --files`.

For process diagnostics, first select one PID with bounded native
metadata such as `ps -eo pid=,comm=,args=` or `ps -p PID -o ...`, then query the
one required edge or field, for example `readlink -e /proc/PID/cwd`,
`readlink -e /proc/PID/exe`, or `cat /proc/PID/cmdline`.

Do not turn process discovery into recursive or shell-expanded search through a
virtual filesystem. If the resolved cwd is the content target, search that
ordinary filesystem path directly after resolving it. When process selection is
ambiguous, narrow the native metadata query by exact PID, command, unit, or user
before reading a field.

## Continuous refinement

Route each demonstrated misuse back to this same skill and guard identity.
Classify the unsafe root and command shape, add the smallest reusable decision
rule, and add hook enforcement only when that rule is mechanically decidable.
Add one failing regression for the misuse and one passing regression for the
nearest legitimate bounded search. Remove overlapping prose or matchers, run
the focused skill and guard checks, then publish and verify the active authority
on provider surfaces.

This workflow owns virtual-root and repository-container root selection.
Conversation-corpus search remains owned by `convo-distilled` and
`corpus-scan-guard`; ordinary search inside one checkout remains scoped `rg`.
