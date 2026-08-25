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
The immutable managed Codex hook directory under `/etc/codex/hooks` is the
deliberate security exception. Its runtime and requirements are store-pinned,
enforcement payloads come from the sealed promotion, and provider adapters plus
their support files link to North's current immutable agent generation.

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

**The agent config is CI-validated** — `.github/workflows/agent-config.yml`
runs `scripts/agent-config-check.sh`: it checks the shared instructions, skills,
and hooks plus the Codex adapter. Run
`scripts/agent-config-check.sh --local` to additionally verify live symlinks,
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
