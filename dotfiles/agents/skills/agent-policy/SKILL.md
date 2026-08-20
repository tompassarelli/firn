---
name: agent-policy
description: >-
  Author, restructure, register, or debug personally owned AGENTS.md policy,
  Codex or Claude skills, switchboard modules, and activation metadata. Use
  whenever changing agent instructions or skills, deciding what must stay
  always loaded versus trigger on demand, locating a projected policy source,
  or verifying that a skill reaches Claude Code and Codex.
---

# Agent policy

Keep one source for each rule and make its loading scope match its trigger.

## Locate authority before editing

Run `agents status` to see live composition and `agents path <name>` to resolve
the owning source. Never edit `~/.agents`, `~/.claude`, `~/.codex`,
`/etc/codex`, or another generated projection. Read each repository's root
`AGENTS.md`, then use a `worktrees/<slug>` lane; never edit `main/` or `pins/`.

Treat personally owned sources under `~/code/nixos-config`, `~/code/north`,
and `~/code/beagle` as the editable policy surface. Inspect project
`AGENTS.md` files outside the owning repository read-only when checking
duplication.

## Choose the loading layer

Keep only rules that must constrain every applicable action in `AGENTS.md`:
safety boundaries, authority and source-of-truth declarations, project
architecture invariants, and irreversible-operation rules. State each once,
at the narrowest directory that always covers its action.

Put a coherent optional workflow in one skill when a user request or task
shape can trigger it reliably. The frontmatter description must name both the
capability and concrete trigger phrases or contexts. Do not create aliases,
compatibility copies, decorative categories, or tiny one-paragraph skills.
Delete replaced prose after the skill is registered and activation is proved.

Use a switchboard module only when instructions, skills, hooks, or agent
templates must activate as one unit. A hook claim belongs in the owning
skill's frontmatter; a set belongs in
`~/code/nixos-config/main/dotfiles/agents/modules.d/<name>.json`.

## Create or revise a skill

For a new skill, run the system skill creator's `scripts/init_skill.py` into
the owning repository. Write imperative instructions and keep detailed
reference material one link deep under `references/` only when it is needed.
Generate `agents/openai.yaml` with human-readable `display_name`, a 25–64
character `short_description`, and a one-sentence `default_prompt` that names
`$skill-name`. Do not add interface fields the operator did not request.

Register a standalone skill in the switchboard's skill inventory and source
resolver. Extend the existing switchboard fixture so path resolution and both
provider links are asserted. Keep third-party and system skills read-only.

## Validate and activate

Run the skill creator's `scripts/quick_validate.py` for each standard skill.
For a switchboard skill whose frontmatter uses extensions such as `hooks` or
`agents`, use its focused switchboard fixture instead; the generic validator
does not accept those fields. Do not rebuild the system for an out-of-store
skill or switchboard source.

After the owning commits land and each `main` is fast-forwarded, run:

```text
agents on <skill>
agents status
agents path <skill>
```

Confirm the reported source resolves to the landed `main`, not a lane or a
projection. Then reap every finished worktree and branch.
