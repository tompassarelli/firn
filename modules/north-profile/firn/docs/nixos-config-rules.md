# System / global config changes — nixos-config rules

Any durable change to the machine's configuration or Firn-owned agent
integration is declared through `~/code/nixos-config`, never left as an
unowned live-system tweak. Declaring the stable wiring does **not** mean putting
every frequently changing byte or child command into a bespoke Nix closure.
Personal agent policy is composed into North's immutable current activation
generation. Firn owns only its Nix-specific fragments, provider adapters,
system packages, services, dotfiles, and Home Manager wiring. A fresh rebuild
must reproduce the integration.

## House style — Nix is the publication boundary, not the development loop

This configuration intentionally optimizes for a machine whose tools and
services change many times per day. Nix owns the stable system shell: boot and
security configuration, accounts, the host package set, durable service
wiring, and pointers to runtime-owned state. It does not own the edit-observe
loop for live tools.

- Classify by feedback loop first. If a change should become observable after
  a reload, restart, or runtime promotion, keep the changing bytes in a live
  checkout, an out-of-store symlink, or an atomic promoted-runtime selector.
  Nix installs the stable pointer and supervision only.
- Prefer Nix-declared out-of-store references for user-owned, frequently edited
  files. Nix owns the destination, wiring, and lifecycle; the live checkout owns
  the bytes. An edit that can safely take effect through reload or restart must
  not require a generation merely to copy those bytes into the store.
- A rebuild is for a real system-generation change. It is never the delivery
  channel for North, Beagle, or another hot-loop checkout. A request whose
  purpose is code adoption identifies a missing promotion/reload channel.
- Purity applies when publishing a generation: the rebuild consumes a committed
  snapshot and switches the exact verified closure. It does not require the
  preceding development loop or every host-management subprocess to be pure.
- Choose one execution boundary deliberately. A hermetic service gets packaged
  runtime inputs. A live host-management adapter gets one declared operational
  path: root-owned wrappers and system tools first, followed only by the user's
  declared Nix package profile when the host package set does not carry a tool.
  User-owned live entrypoints are named explicitly, never found through an
  arbitrary interactive-shell `PATH`. Do not reconstruct the host toolchain one
  missing executable at a time.
The test is simple: if removing the Nix generation step would make the desired
developer loop faster without weakening the eventual published generation,
the generation step does not belong in that loop.

When both designs are correct, out-of-store wins for the developer surface. A
store-managed copy requires a named invariant: runtime immutability is
load-bearing for boot or security code, root-owned enforcement, atomic version
publication, or rollback that must restore those exact bytes.

## Symlinks

Agent discovery pointers are `mkOutOfStoreSymlink`s into North's one current
activation generation under `~/.local/state/north/agents/current`:

- `~/.agents/AGENTS.md` → `instructions/shared/AGENTS.md`;
- `~/.codex/AGENTS.md` → `instructions/codex/AGENTS.md`;
- `~/code/AGENTS.md` → `instructions/code/AGENTS.md`;
- `~/.agents/skills` → `skills/shared`;
- `~/.agents/hooks` → `provider-hooks`.

North publishes no shared docs artifact, so Firn declares no `~/.agents/docs`
projection.

North owns the catalog, permission transition, module/support resolution, atomic
generation, and those projections. Firn owns only stable discovery pointers
and immutable provider wiring. North may maintain exact catalog-owned
compatibility links inside the existing `~/.codex/skills` directory, but Firn
never replaces that directory or its provider-owned `.system` entries. The
`agents` command delegates directly to `north config agents`; it is not a
second reader or writer.
Firn owns individual store-pinned runtime links and provider adapters under
`/etc/codex/hooks`; the adapters point to North's current immutable agent
generation. The directory also contains externally installed North enforcement
links targeting `/var/lib/north-enforcement/active/current`. Firn preserves
those sibling paths and never replaces the shared directory. Their presence
alone does not establish that the separate enforcement deployment is active.

## Shared skill dials

`north config agents` is the only runtime control surface for catalogued
skills, hooks, and modules. It stages a complete generation and atomically
replaces one `current` pointer. `category:` remains optional SKILL.md metadata;
missing metadata is `uncategorized`. Firn's owned skill declares
`category: nixos`.

Home Manager owns only the stable chain:
`~/.agents/skills → ~/.local/state/north/agents/current/skills/shared`. It must
never select individual skills or wire provider discovery directly back to an
owner source.

## CI validation

**The agent config check lives in North** —
`north:socrates/scripts/agent-config-check.sh` checks the shared instructions, skills,
and hooks plus the Codex adapter. Run
`~/code/north/main/socrates/scripts/agent-config-check.sh --local` to additionally verify live symlinks,
the MCP registration, North's SubagentStop provider adapter, and installed
North's OpenAI provider readiness. Normal output is a grouped summary;
`--verbose` prints every assertion. This is the anti-rot gate; keep it green.

## Hooks kill-switch

**Behavior-injecting hooks share one resolved activity authority** — North
publishes every hook's permission, active state, supporting claimants, and
activation paths in `current/activation.json`, so report and enforcement
cannot disagree:

- **Persistent, live flip (all sessions):** `agents off <hook-id>` /
  `agents on <hook-id>` — publishes a new immutable activation generation.
- **Per-session override at launch:** `AGENT_NO_AUTHORING_HOOKS=1 codex` —
  any value except `0`/`false`/empty engages the kill-switch for that session;
  `0`/`false` forces guards live (beats stored activity). The var must be in
  the provider CLI's own launch environment — exporting inside a running
  session does nothing.

Killed = every authoring guard no-ops (beagle SessionStart handshake,
Firn system policy, agent-spawn guard, and tripwire)
— used to pin a neutral, confound-free session.

## Adding new wiring

For anything NOT already wired (a new package, service, dotfile, or symlink), add
it to the appropriate nix module (+ `home.file` / `mkOutOfStoreSymlink`), then
rebuild. Do not drop untracked files into the live system.

After any such change: `git -C ~/code/nixos-config/main status` should have no stray
untracked state, and the change must survive a fresh rebuild. When you make a
global/system edit, say so and commit it — don't leave it dangling in `~`.

## Configuration source and module authoring


The write interface is beagle/nix: edit `#lang beagle/nix` `.bnix` sources and
run `firn repo build` to regenerate their sibling `.nix` targets. Never edit a
generated `.nix`. Both files are committed because the flake reads the Git
tree. Run `firn repo build` before any Nix build after a `.bnix` change.

Selected Clause modules instead use `nixos-config:modules/<name>/tags.clause`
for tag membership and `nixos-config:native/nix/<name>.clause` for the module.
The metadata file explicitly selects Clause and cannot coexist with
`nixos-config:modules/<name>/default.bnix`. Compile its `<name>-module` export
through `firn repo build`, using the runtime's compiler built from
`nixos-config:config/clause-revision`; the generated output remains
`nixos-config:modules/<name>/default.nix`. Shared declarations remain Clause
source. See `nixos-config:native/nix/README.md` for the focused check.
The metadata imports `nixos-config:native/module_metadata.clause` and exports
`metadata(): ModuleMetadata`, supplying automatic tags and opt-in tags once.
The resolver compiles each source once and calls that checked export with the
same pinned compiler. `firn-runtime-update`
produces and binds that compiler for tag, inventory, and build commands. It does not
parse Clause text or read the generated Nix for tags.

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

Native clients with measured smaller memory use may request an allowance
through `machine-capacity`'s `--memory-gib` option; see the owning skill for
admission and scope behavior. Its focused check is
`north:socrates/skills/machine-capacity/scripts/machine-capacity.test.sh`.

Every dotfile has one source under `dotfiles/`. Prefer an out-of-store symlink
for user-owned dotfiles, scripts, and live entrypoints. Use a store-managed copy
only for a named immutability, publication, security, or rollback invariant.

Machine commands are one executable shell file each under `dotfiles/bin/`;
agent tools live in `north:bin/`.
`firn` contains only commands that operate on this repository; general tools
remain standalone commands. Its CLI is entity-first:
`<node> <edge> [<leaf>]`.
