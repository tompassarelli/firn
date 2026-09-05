---
name: nix-development-distilled
description: >-
  Create or repair project-local Nix environments and consumed flake outputs outside nixos-config.
---

# Nix project development

Use the project's existing manifests, flake, lock file, build commands, and
supported platforms as authority. Route NixOS machine configuration to
`firn-distilled`; a project package or shell grants no system-closure access.

Follow source-language policy: new Tom-owned Nix semantics use Beagle/Nix;
existing plain Nix is not automatically a migration task. Keep credentials,
unrequested caches, and global settings out of the change.

Declare only consumed outputs: a development shell, package, app, check, or
exported module. Reuse native toolchain manifests and pin flake inputs. Include
the compiler, package manager, linker, headers, and tools required by the real
build; keep shell hooks minimal and deterministic.

Generate and validate source, then exercise the requested output. Git flakes
ignore untracked files: use an explicit path URL or stage named new files.
Run the nearest actual project command inside the declared environment.
Do not turn ad-hoc PATH assembly or a global toolchain installation into the
normal workflow.

Distinguish evaluation, input, source-filtering, lock, and project-code failures.
Report the working output and untested platform limits.
Full notes: [output and environment design](references/environment-design.md)
and [evaluation and completion](references/evaluation.md).
