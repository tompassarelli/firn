# System / global config changes — nixos-config rules

Any change to the machine's configuration **or** to a coding agent's global setup is made
**idiomatically through `~/code/nixos-config`**, never ad-hoc in the live system.
This covers shared agent config (`AGENTS.md`, `skills/`, `docs/`, `hooks/`),
provider adapters (`dotfiles/claude/`, `dotfiles/codex/`), system packages,
services, dotfiles, and any host / home-manager setting. The whole point is
**reproducibility** — a fresh rebuild on any machine must reproduce the change.

Mechanics of the nix module that does the wiring (writable settings.json
symlink, Claude plugin reconciliation, MCP registration):
`nixos-config:dotfiles/agents/docs/nixos-module.md`.

## Symlinks

`~/.agents/{skills,docs,hooks}`, `~/.codex/{AGENTS.md,config.toml,hooks.json}`,
and `~/.claude/{skills,CLAUDE.md,commands,settings.json,hooks,agents}` are
`mkOutOfStoreSymlink`s into `nixos-config/dotfiles/` (see
`modules/agent-core`, `modules/codex`, and `modules/claude`; generated `.nix`
files are build targets). Editing them edits the repo *directly* and is live
immediately — **but you MUST commit it to `nixos-config`**, or it isn't
reproducible.

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
`dotfiles/agents/hooks/lib/authoring-killswitch.sh`, sourced by every guard
AND by `north config`, so report and enforcement cannot disagree:

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
