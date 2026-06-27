# Handoff: Ultracode vs Lodestar Deep-Dive

> For the next agent picking this up. Read fully before starting.

## What the user wants

A comprehensive deep-dive report analyzing 5 interconnected areas of their Claude Code setup. The user is building a custom "ultracode" replacement using lodestar (claim-based task substrate) + a fleet protocol (role-based multi-agent coordination) + lodestar-web (observability UI). They want to understand whether this override delivers real value, what's missing, and how to make lodestar the natural default for task/thought/project management.

The final deliverable is a **synthesis report** covering all 5 areas with concrete file evidence, not hand-wavy analysis.

## The 5 research streams

A workflow script exists with exact prompts for each stream:
`~/code/nixos-config/.claude/projects/-home-tom-code-nixos-config/76e992b4-e1d7-4fb7-a1a0-e2920f6e2783/workflows/scripts/ultracode-vs-lodestar-deepdive-wf_d222b123-ea2.js`

### 1. Override mechanism (`override-mechanism`)
How ultracode/effort is configured, defaulted, and overridden.
- `~/code/nixos-config/dotfiles/claude/settings.json` — `effortLevel`, thinking keys
- Search `~/.claude/commands/`, `~/.claude/skills/`, `~/code/nixos-config/dotfiles/claude/{commands,skills}` for effort/ultracode definitions
- `~/code/nixos-config/dotfiles/claude/hooks/` — SessionStart hooks that inject ultracode on/off context
- `~/code/nixos-config/dotfiles/claude/hooks/fleet-protocol-guard.sh` — PreToolUse guard blocking raw Agent/Workflow
- `~/code/nixos-config/dotfiles/claude/commands/fleet-guard.md` — toggle command, `~/.claude/fleet-guard.off` sentinel
- Key Qs: How is ultracode ON vs OFF? Minimal change to default OFF? How does fleet-guard interact?

### 2. Fleet substrate (`fleet-substrate`)
The lodestar/fram fleet agent infrastructure.
- `~/code/fleet-data/RUNBOOK.md` — canonical how-to
- `~/code/fleet-data/spawn-agent.sh` — roles, lease-gating, env vars, @agent minting, stop sentinel
- `~/code/lodestar/CLAUDE.md`
- `~/code/nixos-config/dotfiles/claude/docs/fleet-protocol.md`
- CLIs under `~/code/beagle/.scratch/` — presence-cli.clj, msg-cli.clj, fleet-listen-cli.clj, lease-cli.clj
- Ports: :7977 (lodestar work queue), :7978 (fleet coordinator), :8088 (lodestar-web)
- Key Qs: Full lifecycle (spawn->role/lease->steer->observe->stop). What roles exist. What's MISSING vs Anthropic Workflow (fan-out, adversarial verify, synthesis)?

### 3. Lodestar as task management (`lodestar-task-mgmt`)
Why lodestar isn't yet the reflexive "add it here" habit.
- `~/code/lodestar/CLAUDE.md`
- `~/code/lodestar/docs/operating-manual.md`
- `~/code/lodestar/` — bin/, CLI tools (capture/tell/show/ready/next/plate/blocked/agenda/leverage/needs-review/clock)
- `~/code/nixos-config/dotfiles/claude/docs/lodestar-threads.md` and `lodestar-write-safely.md`
- Key Qs: The claim model (thread = claims, lifecycle derived). The intended capture->persist->surface->execute->outcome loop. GAPS and friction that prevent natural adoption. What would make it frictionless?

### 4. Anthropic ultracode (web research) (`anthropic-ultracode-web`)
What Anthropic's ultracode actually is — canonical definition.
- Web search docs.claude.com, anthropic.com, Claude Code docs/changelog
- Effort levels (low/medium/high/xhigh/max)
- Dynamic workflow orchestration — Workflow tool capabilities (pipeline, parallel, barriers, adversarial verify, judge panels, loop-until-dry, completeness critics)
- Key Qs: Precise definition. Specific capabilities lodestar-native ultracode needs to replicate. Where Anthropic's version is strong vs where persistent fleet could do better.

### 5. Framescope override analysis (`lodestar-web-override`)
The observability UI and gain-of-function analysis.
- `~/code/lodestar-web/` — README, what it does (tails agent output streams, /steer endpoint)
- `~/code/fleet-data/RUNBOOK.md` — observe/steer story
- Key Qs: What lodestar-web IS concretely. WHY override Anthropic ultracode (gains: observability, steerability, persistence, role separation, leases). Has the override delivered value SO FAR or is it aspirational? Honest pros/cons.

## Current state of the setup

- **Fleet guard**: OFF (`~/.claude/fleet-guard.off` exists) — raw Agent/Workflow allowed
- **Effort**: xhigh (saved as default)
- **Caveman mode**: full (active all session)
- **Repo**: `~/code/nixos-config`, branch `main`, clean working tree

## What's been tried

3 workflow launches using the saved script above — all cancelled by user (usage/restart concerns, not failures). No research output was captured. This is a fresh start.

## Key docs already in context (read by prior session)

- `~/code/nixos-config/docs/claude/01-canonical.md` — context assembly pipeline, levers table, hooks-vs-skills decision guide
- `~/code/nixos-config/docs/claude/02-local-map.md` — GENERATED local map (settings, hooks, plugins, MCP)
- `~/code/nixos-config/docs/claude/03-lodestar.md` — lodestar substrate: MCP servers, fleet protocol, guard, known gaps
- `~/code/nixos-config/modules/claude/CLAUDE.md` — operational notes (writable symlink, caveman fork+pin, MCP servers)

## User communication style

- Caveman mode active — terse, no filler, fragments OK
- Wants action over explanation
- Gets frustrated with excessive narration or repeated failures
- Prefers `~`-anchored full paths always
- Will say "just commit everything" — means it

## Deliverable format

Structured findings per stream (area, how_it_works, current_state, problems, opportunities, citations) → synthesized into a unified report with concrete recommendations. The workflow script has a JSON schema for each stream's output — use it or match it.
