## Security

Never put plaintext passwords, secrets, API keys, or credentials in this
repository. Store encrypted values under `secrets/` with sops-nix and reference
them through `sops.secrets."name"`. Let the gitleaks pre-commit hook finish
before using `safe-push`; never chain commit and push.

## Source authority

The write interface is beagle/nix: edit `#lang beagle/nix` `.bnix` sources and
run `firn repo build` to regenerate their sibling `.nix` targets. Never edit a
generated `.nix`. Both files are committed because the flake reads the Git
tree. Run `firn repo build` before any Nix build after a `.bnix` change.

Beagle lives at `~/code/beagle/main`. Override `BEAGLE_PATH` only for an
explicit alternate checkout. Query the compiler for forms, signatures, option
paths, types, callers, exports, and targets; never trust a copied inventory.

## Configuration architecture

- Use the `myConfig.modules.*` namespace and keep one package or service per
  module. Multi-file modules separate option declarations in `default.bnix`
  from guarded configuration in `<name>.bnix`.
- Compose modules only through declared `:tags`, `:tags-opt-in`, and
  `:tag-overrides`. Hosts enable tags; explicit host disables subtract from the
  union. Nothing proxies enablement through a bundle.
- Add new modules to `whiterabbit` unless the operator names another host.
- Let the flake's dynamic imports discover a new module directory; do not edit
  the flake to register it.
- Git-add every new `.bnix` and generated `.nix` before evaluation. Untracked
  files are invisible to Nix flakes.
- Co-locate flake inputs in module `:flake-inputs`; never hand-edit generated
  input sections in `flake.bnix`.

## Dotfiles and commands

Every dotfile has one source under `dotfiles/`. Prefer an out-of-store symlink
for user-owned dotfiles, scripts, and live entrypoints. Use a store-managed copy
only for a named immutability, publication, security, or rollback invariant.

Custom commands are one executable shell file each under `dotfiles/bin/`.
`firn` contains only commands that operate on this repository; general tools
remain standalone commands. Its CLI is entity-first:
`<node> <edge> [<leaf>]`.

## Authoring and verification

The `firn` and `beagle-authoring` skills own the operational loop and route to
the focused project guides for schema queries, option renames, repairs, tags,
flake inputs, platform compatibility, input bumps, imports, verification, and
crash recovery. Use those skills when their trigger fires rather than loading
the manuals preemptively.

After a `.bnix` edit, trust the PostToolUse syntax/schema feedback, then run
`firn repo build` and `firn repo validate`. Use `firn repo doctor` only for the
specific untracked, stale-output, cache, orphan, or validation suspicion it can
decide. Agents may run `firn repo upgrade now` in an owned worktree when the
requested outcome includes advancing inputs. Inspect and commit the resulting
changes before running `firn rebuild`, which builds the exact commit snapshot.
Never use raw `nixos-rebuild` or `nh`. Verify only `whiterabbit`, never
`thinkpad-x1e`.
