---
name: firn
description: >-
  Change ~/code/nixos-config or install system-wide software; assess maintained-project system-closure ingress. Other project flakes use nix-development.
grounded: 2026-10-15
written: 2026-10-15
---

# Firn

For a package installation, find its existing module, enable it for the named
host (default `whiterabbit`), validate, commit, and switch. Stay within that
installation and do not audit unrelated configuration, because an install is
one change and an audit is scope Tom did not ask for.

## Configuration changes

1. Read `nixos-config:AGENTS.md` and edit an owned worktree, because the main
   checkout is what other sessions and rebuilds read.
2. Edit authoritative `.nix` modules, because generated files are overwritten.
   Check an uncertain option with `firn schema explain` and the selected
   host's NixOS options, so a guessed type never reaches a rebuild.
3. After composition metadata edits run `firn repo build`, then `firn check`
   before building, because check evaluates options, assertions and Nix
   linters in seconds where a build takes minutes. Stage the exact changed
   paths, including new files, and commit.
4. Switch only when asked, with `firn rebuild` from the committed lane and
   outside the command sandbox, because the sandbox strips sudo's setuid bit.
   It builds exact `HEAD`, so uncommitted work is not included; confirm the
   printed snapshot and the requested installed result.

Use one package or service per module and enable it through declared options
or tags, because dynamic imports discover modules and a stray import bypasses
them. Never use raw `nixos-rebuild` or `nh`, because they skip firn's snapshot
and checks. Verify only `whiterabbit` and `nexus`, because those are the hosts
this repository builds and deploys. Advance inputs with `firn repo upgrade now` only when updating
inputs is in scope, because an upgrade changes every package at once. Use
`firn repo doctor` only for a named suspicion, because it reports noise
otherwise.

## Closure boundary

Keep Tom-maintained and source-declared high-churn projects out of the boot
and system closure by default, because a broken project build must never block
booting or switching. Resolve ownership from source and Git evidence, not a
name or hosting organization, because names mislead. Actual reachability from
`system.build.toplevel` decides membership, because a package or flake input
alone puts nothing in the closure.

Keep such projects in worktrees, filesystem pins, project shells, separate
user runtimes or profiles, atomic runtime selectors, or out-of-store
launchers. An exception requires the complete source-owned stable-machine or
service declaration that global policy specifies, because convenience and
reproducibility alone do not justify coupling the system to a moving project.

Skill-only and other out-of-store policy edits use their projection workflow,
not a system rebuild, because a rebuild does not project them. For module,
closure or recovery detail, read `references/notes.md` and pick the topic.
