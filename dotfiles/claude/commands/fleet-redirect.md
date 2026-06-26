---
description: Toggle the fleet-redirect (raw Agent/Workflow -> fleet) — on | off | status
allowed-tools: Bash(/home/tom/code/nixos-config/dotfiles/claude/hooks/fleet-redirect-toggle.sh:*)
---

!`/home/tom/code/nixos-config/dotfiles/claude/hooks/fleet-redirect-toggle.sh $ARGUMENTS`

Report the resulting state above to me in one short line. If it's now OFF, note that raw Agent/Workflow (incl. ultracode Workflow orchestration) is allowed for this machine until I run `/fleet-redirect on`.
