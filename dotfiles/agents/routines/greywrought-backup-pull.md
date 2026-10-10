---
name: greywrought-backup-pull
kind: systemd-timer
schedule: hourly at :10
owner: manual unit in ~/.config/systemd/user (not Nix-declared)
purpose: Copy the Greywrought game-server backup to this machine every hour.
relates-to: [dotfiles/agents/skills/digitalocean-access, ~/code/greywrought]
expires: never
---

~/.local/libexec/greywrought-pull-backup
