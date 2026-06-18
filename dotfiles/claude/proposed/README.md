# PROPOSED — claim-canonical enforcement layer (NOT auto-enabled)

Design artifacts for making CLAIM-PROJECTION the agent's editing surface for
claim-canonical Beagle sources. Nothing here is wired into the live config: the
hook is not in `settings.json`, and the skill lives under `proposed/skills/` (the
nix module symlinks only `dotfiles/claude/skills/`, so it is NOT discoverable until
moved). Activate DELIBERATELY, and only after a module has actually been adopted as
claim-canonical (today none is — see `code-as-claims/README.md` "Capability vs
adoption").

## Contents

- `hooks/claim-canonical-guard.sh` — PreToolUse guard. On `Edit|Write|MultiEdit`
  it denies (with a redirect to the fram graph-edit tools) IFF the edited file is
  claim-canonical, and is a silent no-op (allow) otherwise. Fail-open.
- `skills/claim-canonical-authoring/SKILL.md` — makes graph-edit the default
  authoring path for claim-canonical files (the model half of the guard).

## The marker (defined by this design; none exists in the repo yet)

A file is claim-canonical iff EITHER:
1. its absolute path is in `$CLAIM_CANONICAL_REGISTRY`
   (default `~/.config/fram/claim-canonical-files`, one path per line) — the
   authoritative, path-based marker, OR
2. its leading comment block contains `;; @claim-canonical` (a Beagle comment, so it
   survives the lossless round-trip and recompiles; after `--render` it lands just
   below the `(define-target clj)` header, which the guard's head-scan tolerates).

ADOPT one module:
```sh
mkdir -p ~/.config/fram
echo /home/tom/code/<repo>/src/<the-one-module>.bclj >> ~/.config/fram/claim-canonical-files
```
DE-ADOPT: remove that line (and the sentinel if stamped). The guard is closed-list,
so it scopes to exactly the adopted file(s) and can never block ordinary edits.

## Activation step A — register the fram MCP server (so the redirect tools exist)

The redirect targets are `mcp__fram__add-def` / `mcp__fram__set-body` /
`mcp__fram__rename` (`mcp__<serverName>__<toolName>`). They must be served by the
fram MCP server AND that server registered as `fram` in this config's `mcpServers`.
Add to `settings.json` (alongside `hooks`):

```json
"mcpServers": {
  "fram": {
    "command": "/home/tom/code/fram/bin/fram-mcp",
    "env": {
      "FRAM_THREADS": "/home/tom/code/fram/threads",
      "FRAM_LOG": "/home/tom/code/fram/claims.log"
    }
  }
}
```

NOTE: the fram catalog is generated from the claim vocabulary (`fram/src/fram/
tools.bclj`); the graph-edit verbs are NOT in it yet. Adding `add-def`/`set-body`/
`rename` as MCP tools (wrapping `resolve.clj`'s modes through the coordinator) is a
prerequisite engine change, separate from this hook/skill design.

## Activation step B — wire the hook into settings.json

Merge this `PreToolUse` entry into the existing `hooks` object in
`dotfiles/claude/settings.json` (it sits next to the current `SessionStart`):

```json
"PreToolUse": [
  {
    "matcher": "Edit|Write|MultiEdit",
    "hooks": [
      {
        "type": "command",
        "command": "/home/tom/code/nixos-config/dotfiles/claude/hooks/claim-canonical-guard.sh",
        "timeout": 10
      }
    ]
  }
]
```

The `matcher` selects which TOOLS the hook runs on; the file-level scoping (only
claim-canonical files deny) is done INSIDE the script, exactly as the existing
`.nix` PostToolUse precedent matches `Write|Edit` then tests `file_path` suffix in
python. Move the script from `proposed/hooks/` to `dotfiles/claude/hooks/` so the
path above resolves.

## Activation step C — make the skill discoverable

Move `proposed/skills/claim-canonical-authoring/` to
`dotfiles/claude/skills/claim-canonical-authoring/` (the nix module symlinks
`skills/`). No rebuild needed — the symlink is live; commit to `nixos-config` for
reproducibility.

## How SessionStart already wires hooks (the pattern this mirrors)

`settings.json` already carries a `hooks.SessionStart` array whose single
`command` runs `hooks/beagle-session-start.sh` and injects context via
`hookSpecificOutput.additionalContext`. This design adds a sibling `hooks.PreToolUse`
array with the same shape (`matcher` + `hooks:[{type:"command",command,timeout}]`),
the only differences being the event name and that PreToolUse can return
`permissionDecision:"deny"` to REFUSE the call (SessionStart only injects context;
PostToolUse fires too late to refuse). Both use python3 for JSON I/O because jq is
absent in this environment — same as `beagle-session-start.sh` and the `.nix`
PostToolUse precedent in `.claude/settings.local.json`.
