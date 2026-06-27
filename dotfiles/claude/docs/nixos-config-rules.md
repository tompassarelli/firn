# System / global config changes — nixos-config rules

Any change to the machine's configuration **or** to Claude's global setup is made
**idiomatically through `~/code/nixos-config`**, never ad-hoc in the live system.
This covers: Claude global config (`skills/`, `CLAUDE.md`, `commands/`,
`settings.json`), system packages, services, dotfiles, and any host / home-manager
setting. The whole point is **reproducibility** — a fresh rebuild on any machine
must reproduce the change.

## Symlinks

`~/.claude/{skills,CLAUDE.md,commands,settings.json,hooks}` are
`mkOutOfStoreSymlink`s into `nixos-config/dotfiles/claude/` (see
`modules/claude/default.nix`). Editing them edits the repo *directly* and is
live immediately (no rebuild) — **but you MUST commit it to `nixos-config`**,
or it isn't reproducible. (`hooks/` was nix-wired 2026-06-20; until the next
rebuild creates the symlink, `settings.json` still reaches them by absolute
repo path, which also works.)

## CI validation

**The Claude config is CI-validated** — `.github/workflows/claude-config.yml`
runs `scripts/claude-config-check.sh`: shellchecks the hooks, JSON-validates
`settings.json`, and asserts every wired hook path exists + is executable. Run
`scripts/claude-config-check.sh --local` on the machine to ALSO `command -v`
the CLIs this file names (so a removed/renamed tool fails loudly instead of
rotting silently). This is the anti-rot gate; keep it green.

## Hooks kill-switch

**Behavior-injecting hooks have an opt-out kill-switch:**
`CLAUDE_NO_AUTHORING_HOOKS=1` makes the SessionStart beagle handshake and the
PreToolUse claim-canonical guard no-op — used to pin a neutral, confound-free
session (e.g. for experiments). Unset = normal behavior.

## Adding new wiring

For anything NOT already wired (a new package, service, dotfile, or symlink), add
it to the appropriate nix module (+ `home.file` / `mkOutOfStoreSymlink`), then
rebuild. Do not drop untracked files into the live system.

After any such change: `git -C ~/code/nixos-config status` should have no stray
untracked state, and the change must survive a fresh rebuild. When you make a
global/system edit, say so and commit it — don't leave it dangling in `~`.
