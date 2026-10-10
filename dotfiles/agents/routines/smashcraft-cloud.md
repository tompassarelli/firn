---
name: smashcraft-cloud
kind: cloud-routine
schedule: on demand (leash runs it)
owner: dotfiles/agents/skills/cloud-workers/SKILL.md
purpose: The one reusable cloud routine for smashcraft code-only worker tasks; the lead rewrites its brief per run.
relates-to: [dotfiles/agents/skills/cloud-workers/SKILL.md, dotfiles/agents/skills/cloud-workers/references/remote-trigger.md, dotfiles/agents/routines/leash.md, https://github.com/tompassarelli/smashcraft]
expires: never
---

RemoteTrigger routine trig_01RoHaKMjMDSpHAouCU3FkmU for tompassarelli/smashcraft. Per run, update its brief through RemoteTrigger with a fresh v4 UUID and session_context.model set, then run it in a separate later call; the brief follows the cloud-workers skill and ends with "push to claude/<name>; it lands itself if it passes". Delete it only at claude.ai/code/routines.
