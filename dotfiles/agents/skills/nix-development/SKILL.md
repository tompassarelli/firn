---
name: nix-development
description: >-
  Create or repair project-local Nix environments and consumed flake outputs outside nixos-config.
---

# Project Nix

- Use existing manifests, flake locks, commands and supported platforms; route system configuration to `firn`.
- Follow the project's typed source and immutable compiler pin for new Tom-owned Nix semantics.
- Leave working plain Nix unchanged outside the requested semantic edit.
- Declare only consumed shells, packages, apps, checks or modules and reuse native toolchain manifests.
- Include the real build's compiler, package manager, linker, headers and tools with minimal deterministic shell hooks.
- Generate and validate source, then run the actual project command inside the declared environment.
- Stage named new Git-flake inputs or use an explicit path URL.
- Separate evaluation/input/filtering/lock failures from project failures.
- Keep credentials, unrequested caches/global settings and ad-hoc PATH installations outside the change.
- Report the working output and platform limits.

Use [environment design](references/environment-design.md) or [evaluation](references/evaluation.md) for a named unresolved detail.
