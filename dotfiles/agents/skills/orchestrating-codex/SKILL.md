---
name: orchestrating-codex
agents: [claude]
description: >-
  Run work through a Codex lead session that Claude supervises: start it, give it a goal, message it, watch its worker tree and keep it on a tight leash. Use when Tom asks to drive work through Codex, or for a Codex lead or orchestrator.
grounded: 2026-10-09
written: 2026-10-09
---

# Supervise a Codex lead

- Use `codex-lead --help` for start/id/send/goal/status/workers syntax.
- Never type into its window or take Tom's focus.
- Assign SOL-starting bands to the Codex lead and Claude-starting bands to Claude workers.
- Read `workers`; choose tiers from the plan and `worker-ledger --summary`, never low/max or Astra without Tom naming it.
- Write `~/.local/state/agents/handoffs/codex-lead-brief.md` with scope, first reads, ordered queue, checks, files, ETA and the lead's staffing/landing/status role.
- Require worker reports beginning `Done:`, `Not done:` or `Blocked:` and brief fields `Item`, `Category`, plus `Follows` on retries/escalations/continuations.
- Start the lead with `codex-lead start BRIEF`.
- Use `CODEX_LEAD_THREAD=<id>` for an existing live lead.
- Give it a goal closing every ordered item on GitHub or naming a blocker with evidence and an owner.
- Start all independent items together; open/claim Claude-held items and tell the lead before staffing them.
- Share 20 Actions jobs and 5,000 API calls/hour through `github-actions`; confirm the exact revision before farm dispatch.
- Wait on farm/CI with one blocking repository command or `gh run watch RUN --exit-status`.
- Never poll in a loop.
- Monitor `~/.local/state/agents/handoffs/codex-lead-peer.md` for `PEER`/`HANDOFF`, with a 30-minute timeout rearmed on expiry.
- Escalate a worker past 2× ETA, a second `Not done` on one box, or an unavailable next plan tier with `PEER <HH:MM> <repo#N>: <tried by tiers>; <failure>; <next idea>`.
- Answer PEER within minutes through `codex-lead send` with smaller pieces and leads.
- After that attempt fails, append `HANDOFF <HH:MM> <repo#N>: <state, branch, evidence>` and transfer staffing to Claude.
- Keep `codex-lead-status.md` in the same handoffs directory current after every landing, failure and staffing change, with Updated/Running/Closed/Blocked/Next/Needs Tom.
- Include item, worker path, model/effort and ETA under Running; numbers under Closed; evidence and owner under Blocked.
- Check `codex-lead status`, `codex-lead workers`, issue closures, `threads list` claims and capacity at most every 20 minutes until the queue empties.
- Correct idle workers at 10+ minutes, overruns at 2× ETA, wrong tiers, missing claims/report fields and serialized independent work.
- Map every open issue to a Codex worker idle under 10 minutes, a running Claude worker, or a named blocker; correct closed-issue workers and short staffing too.
- Give slots to main-red issues, correctness/gameplay, release gates, then polish.
- Ask owners to release blocking exclusive leases or over-pressure native pools at a safe phase.
- Send one correction message per check, naming each gap/fix and requesting one owner/blocker line per issue.
- Refresh the goal hourly and immediately on queue changes.
- Keep supervision scheduled for the goal's lifetime.
- Compare same-category Claude/Codex ledger rows only in this mixed-provider mode.
- Use the ledger over the Opus 5.5 medium/Astra chart prior of 20–40% cost.
- Cross-review netcode, rollback/determinism, save/replay formats and balance gates before landing.
- Mark Codex pieces `Review: <item> <branch> <commit>` in status; have Claude report concrete defects within 20 minutes and land after answers or 20 minutes without findings.
- Send Claude-landed commits to the lead for one SOL high reviewer per item.
- Require file:line and failing case and fix forward.
- Never use `codex queue`; deliver mid-turn corrections through `codex-lead send`.
- Send only to threads with live sessions; restart a finished exec session before expecting replies.
- Ask the lead for encrypted worker briefs rather than reading them from its log.
- Read [session diagnostics](references/session-diagnostics.md) only for socket, thread/log lookup or test-thread cleanup.
- Report a PEER line instead of additional checks.
- Report completion when the queue is empty.
