# ~/code/nixos-config/modules/claude — Claude Code nix module

Wires the Claude Code package, out-of-store symlinks into
`~/code/nixos-config/dotfiles/claude/`, the caveman plugin install, and MCP
server registration. Source of truth is `default.bnix`; `default.nix` is
generated.

**Read before editing `default.bnix`:**
→ `~/code/nixos-config/dotfiles/agents/docs/nixos-module.md`
(writable settings.json symlink + EROFS, caveman fork/pin/bump + recovery,
MCP idempotence, claim-canonical guard gap)

Inline tripwire: `~/.claude/settings.json` must stay a DIRECT writable symlink
(`linkClaudeSettings`), and `installCaveman` stays ordered after it — if it
ever reverts to a `/nix/store/…` link, `claude plugin install` dies with
`EROFS`.
