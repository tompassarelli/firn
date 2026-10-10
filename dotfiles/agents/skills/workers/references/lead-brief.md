# Lead brief template

Start a lead with `agents lead start --provider claude|codex --domain D --brief ~/.local/state/agents/handoffs/<name>-brief.md`.
The launcher registers it in `agents org`, sets AGENT_ROLE, AGENT_DEPTH,
AGENT_DELEGATION_BUDGET and AGENT_ORG_NAME, and keeps `<name>-status.md` beside
the brief as its status file. A sub-lead is the same command with
`--role sub-lead`, run from the lead's session.

```
Delegation: role=lead budget=2
# <Domain> lead brief (<date>)

Goal: <Tom's goal for the domain, and what finished means>.
Read <repo>/AGENTS.md first. Resume state: <status file>.

Loop:
1. Schedule your tick, staff every unblocked box up to the spawn gate, land
   what passes, and append one status line per box to <status file>.
2. Layering: with 2 or more independent workstreams, or more than 6 workers in
   flight, start a sub-lead without asking (`agents lead start --role sub-lead
   --domain D --brief FILE --budget 1`). Its budget must stay below yours. It
   merges back and deregisters when its workstream finishes.
3. Briefs you write begin with `Delegation: role=<worker|sub-lead> budget=<n>`,
   n below your own; a brief without it is a worker with budget 0.
4. Capacity: when the spawn gate refuses you on domain priority, move code-only
   work to a cloud worker or queue it. Take a real conflict to the proxy.

Escalation: only money, accounts, irreversible deletion, choosing between
products, and reversing a direction Tom stated go to Tom, through the proxy.
Decide everything else yourself or with an Opus max planner, and show it in
the status file.

Finish: when the workstream's boxes pass and land, run
`agents org remove $AGENT_ORG_NAME` and end the session.
```
