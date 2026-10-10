---
name: digitalocean-access
description: >-
  Access Tom's DigitalOcean account, or restore the destroyed greywrought-dev server, and run authorized remote development work.
grounded: 2026-10-10
written: 2026-10-10
metadata:
  kind: playbook
---

# DigitalOcean

- greywrought-dev was destroyed on 2026-10-10 to stop billing; the account has no droplets, snapshots, volumes or reserved IPs.
- Restore it only when Tom resumes Greywrought, following `~/archive/greywrought-dev-2026-10-10/PLAYBOOK.md`, which holds the world save, configs and unpushed work.
- Run account operations through `nix shell nixpkgs#doctl` with `DIGITALOCEAN_ACCESS_TOKEN` decrypted from `nixos-config:secrets/digitalocean.yaml` (key `token`, root-readable age key `/var/lib/sops-nix/key.txt`), and never print it.
- Ask before creating billable resources; destroy only resources Tom names.
- After a restore, connect with `/home/tom/.ssh/greywrought-wiki-admin`, batch mode, identities-only, strict host-key checking and a bounded timeout; accept a new host key only after matching the console fingerprint.
- Run remote work with requested model/effort/permissions and verify accepted ownership plus useful activity before reporting launch.
- Keep development resources/listeners private.

Use [access](references/access.md), [remote agents](references/remote-agents.md), [phone jobs](references/phone-jobs.md) or [Ubuntu sandbox](references/ubuntu-sandbox.md) for detail once a server exists again.
