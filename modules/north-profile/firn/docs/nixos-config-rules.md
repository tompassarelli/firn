# System / global config changes — nixos-config rules

Any change to the machine's configuration or Firn-owned agent integration is
made **idiomatically through `~/code/nixos-config`**, never ad-hoc in the live
system. Personal agent policy is composed by
`~/code/north/main/profiles/tom`; Firn owns only its Nix-specific fragments,
provider adapters, system packages, services, dotfiles, and Home Manager
wiring. A fresh rebuild must reproduce the integration.

Mechanics of the nix module that does the wiring (writable settings.json
symlink, Claude plugin reconciliation, MCP registration):
`nixos-config:modules/north-profile/firn/docs/nixos-module.md`.

## Symlinks

`~/.agents/{AGENTS.md,docs,hooks}` are `mkOutOfStoreSymlink`s into North's
composed profile. `~/.agents/skills` instead points at the atomic runtime farm
`~/.local/state/north/skills`; North inventories the complete source at
`~/code/north/main/profiles/tom/skills` and publishes resolved immutable
generations there. Provider discovery paths such as
`~/.claude/{skills,CLAUDE.md,hooks}`, `~/.codex/AGENTS.md`, and
`~/.hermes/SOUL.md` compose through `~/.agents`; provider-specific adapters
remain in `nixos-config`. Claude's writable `settings.json` is seeded from the
generation rather than symlinked. The immutable managed Codex hook directory
under `/etc/codex/hooks` is the deliberate security exception and sources each
hook from its owning locked flake input.

## Shared skill dials

`north config skills` is the only runtime control surface for the shared farm.
It resolves item over category over all over default-on, stages a complete
generation, and atomically replaces the farm pointer. `category:` is optional
SKILL.md frontmatter; missing metadata is the `uncategorized` category. Firn's
owned skill declares `category: nixos`. Provider/plugin-contributed skills
remain outside this farm and are not toggled by North.

Home Manager owns only the stable chain:
`~/.claude/skills → ~/.agents/skills → ~/.local/state/north/skills`. It must
never select individual skills or wire provider discovery directly back to the
source profile.

## CI validation

**The agent config is CI-validated** — `.github/workflows/agent-config.yml`
runs `scripts/agent-config-check.sh`: it checks the shared instructions, skills,
and hooks plus both the Claude and Codex adapters. Run
`scripts/agent-config-check.sh --local` to additionally verify live symlinks,
both MCP registrations, external North lifecycle hooks, and installed North's
Anthropic/OpenAI provider readiness. Normal output is a grouped summary;
`--verbose` prints every assertion. `scripts/claude-config-check.sh` remains a
compatibility entry point. This is the anti-rot gate; keep it green.

## Hooks kill-switch

**Behavior-injecting hooks share one kill-switch** — semantics live in
`~/.agents/hooks/lib/authoring-killswitch.sh`, sourced by every guard and by
`north config`, so report and enforcement cannot disagree:

- **Persistent, live flip (all sessions):** `north config guards off` /
  `guards on` — writes `guards=on|off` to
  `~/.local/state/north/harness.conf`; hooks re-read it on every call, so it
  takes effect immediately, no relaunch. A pre-migration
  `~/.claude/my-config.state` is a read-only fallback only while the canonical
  file is absent.
- **Per-session override at launch:** `AGENT_NO_AUTHORING_HOOKS=1 claude` (or
  `AGENT_NO_AUTHORING_HOOKS=1 codex`) —
  any value except `0`/`false`/empty engages the kill-switch for that session;
  `0`/`false` forces guards LIVE (beats the state file). The var must be in
  the provider CLI's own launch environment — exporting inside a running
  session does nothing. `CLAUDE_NO_AUTHORING_HOOKS` remains a compatibility
  alias.

Killed = every authoring guard no-ops (beagle SessionStart handshake,
code-upstream guard, firn guard, racket-build guard, agent-spawn-guard,
tripwire, north-clock guard) — used to pin a neutral, confound-free session.

## Adding new wiring

For anything NOT already wired (a new package, service, dotfile, or symlink), add
it to the appropriate nix module (+ `home.file` / `mkOutOfStoreSymlink`), then
rebuild. Do not drop untracked files into the live system.

After any such change: `git -C ~/code/nixos-config/main status` should have no stray
untracked state, and the change must survive a fresh rebuild. When you make a
global/system edit, say so and commit it — don't leave it dangling in `~`.
