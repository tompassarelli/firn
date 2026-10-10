---
name: cloud-workers
agents: [claude]
description: >-
  Run every code-only worker task in Anthropic's cloud first through Claude
  Code routines with the RemoteTrigger tool; local workers take only Warcraft
  clients, private game assets, the LAN pool or unpushed local state.
grounded: 2026-10-09
written: 2026-10-09
---

# Cloud workers

- Use only public Wisp/Smashcraft code tasks without private/local inputs, Warcraft clients or Tom's install.
- Budget 4 cores, 15 GB, Bun 1.4.2, gcc/clang and 100 runs/hour/account; use pinned Bun 1.3.13 for these repositories.
- Build Lua 5.3.6 with LUA_32BITS or use Wisp's pinned command when Lua is required.
- Keep account extra usage off so plan limits pause work instead of billing.
- Run RemoteTrigger only from the main session and reuse one routine/repo.
- Set `session_context.model` on every routine update: `claude-opus-5-5` for meaningful or complex work, `claude-haiku-5-5` for very simple mechanical work; never leave it unset.
- Update the routine brief with a fresh v4 UUID, run it and retain its returned session ID.
- Read get_run_log or list_runs for its result.
- Put goal/files/Done when/ETA in a self-contained brief with `Refs repo#N` commits and no push notifications.
- End each prompt with `push to claude/<name>; it lands itself if it passes`.
- Let Autoland rebase/check/farm/compare and land sequentially; fix conflicts or new failures on the same branch.
- Tell each brief to fetch and rebase onto origin/main right before its push; most cloud refusals are conflicts from main moving during the run.
- Retry a branch through `gh workflow run autoland.yml -R tompassarelli/<repo> -f branch=claude/<name>`.
- Land workflow changes locally through safe-push.

Use [RemoteTrigger schema](references/remote-trigger.md) when creating a routine; delete routines only at claude.ai/code/routines.
Use each repository's indexed docs/ci.md Autoland topic for landing details.
