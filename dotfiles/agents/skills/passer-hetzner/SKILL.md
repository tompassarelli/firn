---
name: passer-hetzner
description: >-
  Access Tom's Hetzner account for Passer Systems (Robot dedicated servers), including the GEX45 GPU box.
grounded: 2026-10-10
written: 2026-10-10
---

# Passer Hetzner

- Account: Hetzner Robot (`https://robot.hetzner.com`) for Passer Systems; use Tom's established browser session and never create accounts or order/cancel servers without asking.
- Server: GEX45 dedicated GPU box, ordered 2026-10-10 with public-key login only (no root password is emailed).
- SSH alias `gex45` in `~/.ssh/config`: user `root`, key `~/.ssh/hetzner-gex45`, identities-only.
- If `HostName` is still `CHANGE_ME_SERVER_IP`, take the IP from Robot's server list or Hetzner's ready email and update the alias.
- Public key `~/.ssh/hetzner-gex45.pub` (`tom@hetzner-gex45`) is plain config, not a sops secret; the private key stays only in `~/.ssh`.
- Connect with batch mode, a bounded timeout and strict host-key checking after the first accepted key; stop on host-key mismatch.
- Verify hostname before writes; Robot rescue/reinstall wipes the disk, so ask before using either.
