---
description: Toggle the fleet-protocol guard (raw Agent/Workflow block) — on | off | status
allowed-tools: Bash(/home/tom/code/nixos-config/dotfiles/claude/hooks/fleet-guard-toggle.sh:*)
---

!`/home/tom/code/nixos-config/dotfiles/claude/hooks/fleet-guard-toggle.sh $ARGUMENTS`

Report the resulting state above to me in one short line. If it's now OFF, note that raw Agent/Workflow (incl. ultracode Workflow orchestration) is allowed for this machine until I run `/fleet-guard on`.
