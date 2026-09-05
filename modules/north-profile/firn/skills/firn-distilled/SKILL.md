---
name: firn-distilled
description: >-
  Change ~/code/nixos-config or install system-wide software; assess maintained-project system-closure ingress. Other project flakes use nix-development.
---

# Firn

For a package installation, find its existing module, enable it for the named
host (default `whiterabbit`), validate, commit, and switch. Stay within that
installation; do not audit unrelated configuration.

## Configuration changes

1. Read `nixos-config:AGENTS.md` and edit an owned worktree.
2. Query uncertain package, schema, or compiler facts. Edit authoritative
   Beagle/Nix `.bnix`, never generated `.nix`.
3. After `.bnix` changes, run `firn repo build` then `firn repo validate`.
   Stage exact source/target pairs, including new files, and commit.
4. When switching is requested, run `firn rebuild` from the committed lane.
   It builds exact `HEAD`; unrelated uncommitted work is not included.
   Confirm the printed snapshot and requested installed result.

Use one package/service per module; dynamic imports discover it. Enable through
declared options/tags. Never use raw `nixos-rebuild` or `nh`; verify only
`whiterabbit`. Advance inputs with `firn repo upgrade now` only when updating
inputs is in scope. Use `firn repo doctor` only for a named suspicion.

## Closure boundary

Tom-maintained and source-declared high-churn projects stay out of the boot/
system closure by default. Resolve ownership from source/Git evidence, not a
name or hosting organization. Actual reachability from `system.build.toplevel`
decides membership; a package or flake input alone does not.

Use worktrees, filesystem pins, project shells, separate user runtimes/profiles,
atomic runtime selectors, or out-of-store launchers. An exception requires the
complete source-owned stable-machine/service declaration specified by global
policy; convenience and reproducibility alone do not qualify.

Skill-only or other out-of-store policy edits use their projection workflow,
not a system rebuild. For module, closure, or recovery detail, resolve
`agents path firn-reference` and select the relevant topic.
