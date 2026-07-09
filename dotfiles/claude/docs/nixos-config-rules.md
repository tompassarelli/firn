# System / global config changes — nixos-config rules

Any change to the machine's configuration **or** to Claude's global setup is made
**idiomatically through `~/code/nixos-config`**, never ad-hoc in the live system.
This covers: Claude global config (`skills/`, `CLAUDE.md`, `commands/`,
`settings.json`), system packages, services, dotfiles, and any host / home-manager
setting. The whole point is **reproducibility** — a fresh rebuild on any machine
must reproduce the change.

Mechanics of the nix module that does the wiring (writable settings.json
symlink, caveman plugin install, MCP registration):
`~/code/nixos-config/dotfiles/claude/docs/nixos-module.md`.

## Symlinks

`~/.claude/{skills,CLAUDE.md,commands,settings.json,hooks,agents}` are
`mkOutOfStoreSymlink`s into `nixos-config/dotfiles/claude/` (see
`modules/claude/default.bnix` — `default.nix` is generated). Editing them edits
the repo *directly* and is live immediately (no rebuild) — **but you MUST
commit it to `nixos-config`**, or it isn't reproducible. (`docs/` is
intentionally not wired — pointers use full repo paths.)

## CI validation

**The Claude config is CI-validated** — `.github/workflows/claude-config.yml`
runs `scripts/claude-config-check.sh`: shellchecks the hooks, JSON-validates
`settings.json`, and asserts every wired hook path exists + is executable. Run
`scripts/claude-config-check.sh --local` on the machine to ALSO `command -v`
the CLIs this file names (so a removed/renamed tool fails loudly instead of
rotting silently). This is the anti-rot gate; keep it green.

## Hooks kill-switch

**Behavior-injecting hooks share one kill-switch** — semantics live in
`dotfiles/claude/hooks/lib/authoring-killswitch.sh`, sourced by every guard
AND by `my-agent-config`, so report and enforcement cannot disagree:

- **Persistent, live flip (all sessions):** `my-agent-config guards off` /
  `guards on` — writes `guards=on|off` to `~/.claude/my-config.state`; hooks
  re-read it on every call, so it takes effect immediately, no relaunch.
- **Per-session override at launch:** `CLAUDE_NO_AUTHORING_HOOKS=1 claude` —
  any value except `0`/`false`/empty engages the kill-switch for that session;
  `0`/`false` forces guards LIVE (beats the state file). The var must be in
  Claude Code's own environment, i.e. set when launching — exporting inside a
  running session does nothing.

Killed = every authoring guard no-ops (beagle SessionStart handshake,
code-upstream guard, firn guard, racket-build guard, agent-spawn-guard,
tripwire, north-clock guard) — used to pin a neutral, confound-free session.

## Adding new wiring

For anything NOT already wired (a new package, service, dotfile, or symlink), add
it to the appropriate nix module (+ `home.file` / `mkOutOfStoreSymlink`), then
rebuild. Do not drop untracked files into the live system.

After any such change: `git -C ~/code/nixos-config status` should have no stray
untracked state, and the change must survive a fresh rebuild. When you make a
global/system edit, say so and commit it — don't leave it dangling in `~`.
