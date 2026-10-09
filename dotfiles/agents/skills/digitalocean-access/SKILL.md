---
name: digitalocean-access
description: >-
  Access Tom's existing DigitalOcean account or greywrought-dev server and run authorized remote development work.
grounded: 2026-10-09
written: 2026-10-09
---

# DigitalOcean

- Reuse the existing server unless provisioning/billing is explicitly requested.
- Connect to `tom@137.184.38.104` with `/home/tom/.ssh/greywrought-wiki-admin`, batch mode, identities-only, strict host-key checking and a bounded timeout.
- Verify hostname and the requested service before writes; stop on host-key mismatch.
- Use an established browser session or doctl context for account operations and inspect credential existence only.
- Run remote work with requested model/effort/permissions and verify accepted ownership plus useful activity before reporting launch.
- Preserve accounts/sign-ins and use the existing Remote Control app-server's normal thread listing for phone-visible jobs.
- Keep development resources/listeners private and preserve `/srv/greywrought/current` and production service state.

Use [access](references/access.md), [remote agents](references/remote-agents.md), [phone jobs](references/phone-jobs.md) or [Ubuntu sandbox](references/ubuntu-sandbox.md) for the operation's unresolved detail.
