---
name: digitalocean-access-distilled
description: >-
  Access Tom's existing DigitalOcean account or greywrought-dev server and run authorized remote development work.
---

# DigitalOcean access

Existing SSH access and account/API access prove different things. Reuse the
existing server unless provisioning or billing changes are explicitly in scope.

The verified development host is `tom@137.184.38.104`. Use
`/home/tom/.ssh/greywrought-wiki-admin` with batch mode, identities-only,
strict host-key checking, and a bounded connection timeout. Verify hostname
and the requested service before writes. A host-key mismatch stops access;
never disable checking or cycle through old addresses.

Use an established browser session or doctl context for account operations.
Inspect credential existence, not contents. Follow global secure-transfer
rules for required access; add no API billing or unrequested token mechanism.

Remote work must use the requested model/effort and effective permissions.
Verify ownership acceptance and useful activity before reporting launch.
Preserve existing sign-ins and accounts. Phone monitoring requires the existing
Remote Control app-server and a job visible in its normal thread listing.

This server also hosts the public game. Bound development resources, keep test
listeners private, and do not change `/srv/greywrought/current` or restart
production merely to run development.

Read the relevant full notes before that operation:
[SSH and account access](references/access.md),
[remote agents and account pools](references/remote-agents.md),
[phone-visible jobs](references/phone-jobs.md), or
[Ubuntu sandbox repair](references/ubuntu-sandbox.md).
