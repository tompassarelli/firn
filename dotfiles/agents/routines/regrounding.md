---
name: regrounding
kind: session-cron
schedule: 7,27,47 * * * *
owner: dotfiles/agents/skills/workers/SKILL.md
purpose: Every 20 minutes a lead with a goal rebuilds its DAG and staffs every unblocked node, so Tom never has to prompt a regrounding.
relates-to: [dotfiles/agents/hooks/lead-regrounding.sh, dotfiles/agents/skills/workers/SKILL.md, dotfiles/agents/skills/auto-wake/SKILL.md]
expires: never
---

Lead regrounding tick (self-scheduled, not Tom). 0. Run `threads unowned` first; before any other step give each priority:now UNOWNED row a worker (cloud first when code-only) or `threads block <repo#N> <reason>`, capped only by the spawn gate. 1. Reread the goal and the status file ~/.local/state/agents/handoffs/claude-lead-status.md. 2. Rebuild the DAG from the goal's GitHub issues, main CI, cloud runs and queued landings. 3. Name the critical path's longest wait and attack it: batch ready lanes into one landing, run unknown-cause bugs as 2-3 parallel hypotheses, have art or judged work render 2-4 variants per pass and judge once, and send code-only work to cloud workers. 4. Staff every unblocked node up to the spawn gate and recycle workers per the workers skill (45 minutes or 350k context) from a handoff. 5. Close issues whose boxes passed. 6. Write one status line ending with the `threads unowned` summary counts.
