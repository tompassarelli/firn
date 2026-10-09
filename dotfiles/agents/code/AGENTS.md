# Code layout

- Treat `~/code/<project>/` as a container with `main/`, `worktrees/<slug>/` and immutable `pins/<full-object-id>/`.
- Treat `~/code/resources/` as read-only third-party material and check licenses before reuse.
- Keep `~/code/clients/` confidential and runtime data directories outside project ownership.
- Use `repo-safety` for worktree creation, landing, rescue and pin retirement.
