# ~/code/nixos-config/modules/claude — Claude Code nix module

Wires the Claude Code package, out-of-store symlinks into
server registration. Source of truth is `default.bnix`; `default.nix` is
generated.

**Read before editing `default.bnix`:**
→ `~/code/nixos-config/modules/north-profile/firn/docs/nixos-module.md`
MCP idempotence, claim-canonical guard gap)

Inline tripwire: `~/.claude/settings.json` must stay a writable regular runtime
file initialized by `seedClaudeSettings`, never a symlink into either the Nix
store or `~/code/nixos-config`. The committed generation seed converges on
every activation; Claude's `/effort` and plugin writes remain valid writable
seed activation so supported plugin state is reconciled afterward — a
store-backed runtime target makes `claude plugin install` die with `EROFS`.
