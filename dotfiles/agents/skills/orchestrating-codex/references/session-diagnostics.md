# Session diagnostics

- Let `codex-lead` resolve the listening socket under `/tmp/codex-daemon-1000/` on each call; never rely on a stale app-server-control symlink.
- Start a TUI with its prompt argument to create its thread; never type into its window.
- Read thread data under `~/code/north-data/codex-pooled/sqlite/state_5.sqlite`, tables `threads` and `thread_spawn_edges`, only for a specific unresolved lookup.
- Read session logs under `~/code/north-data/codex-pooled/sessions/YYYY/MM/DD/` only for that lookup.
- Archive your test threads with `codex archive --remote unix://<socket> <id>`.
