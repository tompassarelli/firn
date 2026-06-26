# Writable dotfiles escape hatch

## The problem

Home-manager manages dotfiles by building a replica directory tree inside the nix
store, then symlinking your home directory to that tree. When you use
`mkOutOfStoreSymlink`, the replica entry is a symlink pointing back to your repo
file. The result is a two-hop chain:

```
~/.claude/settings.json
  → /nix/store/<hash>-home-manager-files/.claude/settings.json   (nix store, read-only dir)
    → ~/code/nixos-config/dotfiles/claude/settings.json          (repo, writable)
```

Reading works — the OS follows both hops. But tools that do **atomic writes**
(create a temp file in the same directory, then rename) try to create a new file
in the nix store directory from hop 1. The store is read-only, so the write fails.

## When to use this pattern

When an external tool needs to **write** to a managed dotfile (not just read it).
The symptom is an `EROFS: read-only file system` error on a `.tmp` file inside
`/nix/store/`.

## The fix: `home.activation` instead of `home.file`

Replace the `home.file` entry with an activation script that creates a direct
symlink, bypassing home-manager's store replica entirely.

Before (broken for writes):

```clojure
{".claude/settings.json"
  {:source
    (config.lib.file.mkOutOfStoreSymlink
      (s config.home.homeDirectory
        "/code/nixos-config/dotfiles/claude/settings.json"))}}
```

After (direct symlink, writable):

```clojure
:home.activation.linkClaudeSettings
  (config.lib.dag.entryAfter ["writeBoundary"]
    (s "run ln -sfn "
       config.home.homeDirectory
       "/code/nixos-config/dotfiles/claude/settings.json"
       " $HOME/.claude/settings.json\n"))
```

Result: one-hop symlink, temp files land in the repo directory.

```
~/.claude/settings.json → ~/code/nixos-config/dotfiles/claude/settings.json
```

## Trade-offs vs home.file

- **No automatic cleanup.** If you remove the activation script, the symlink
  stays. Delete it manually or add a removal command.
- **No conflict detection.** `ln -sfn` silently overwrites. `home.file` warns
  if an unmanaged file already exists at the path.
- **No generation rollback.** Activation scripts run forward only.

For read-only dotfiles, prefer `home.file` + `mkOutOfStoreSymlink` — the two-hop
chain is fine and you get the safety net. Only use this escape hatch for files
that external tools need to write to.

## Current usage

- `modules/claude/default.bnix`: `settings.json` uses activation (Claude Code's
  `/effort` command does atomic writes). All other `.claude/*` entries
  (commands, skills, CLAUDE.md, hooks) stay on `home.file`.
