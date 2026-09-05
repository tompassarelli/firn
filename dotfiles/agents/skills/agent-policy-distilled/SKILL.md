---
name: agent-policy-distilled
description: >-
  Author, locate, register, or activate source-owned agent instructions, skills, hooks, and modules.
---

# Agent policy

Keep one source for each rule. Use `agents status`, `agents inspect <id>`, and
`agents path <id>` to resolve the live catalog and owner; do not infer source
locations from projection paths or remembered repository layouts.

Use the nearest bootstrap for universal boundaries, a skill for a triggered
workflow, a module for a group of registered units, and hook code for
mechanical enforcement. Permission and resolved activity are distinct.

## Distilled guides and full notes

Keep trigger descriptions short and distilled guides complete for ordinary
execution. Full notes retain constraints, rationale, examples, alternatives,
and clearly labeled exploratory ideas for future re-distillation. Read them
for a named detail or when re-distilling; do not load them routinely. Split
long notes by topic and link the relevant file from the guide or reference
index. Update both layers when an adopted rule changes.

## Change and activate

1. Read owner instructions; edit an owned worktree, never a projection or pin.
2. Follow `skill-creator`. Register each identity once; preserve explicit
   module membership and hook events. Do not add aliases or duplicate rules.
3. Run the relevant source/catalog check. Local skill edits need no NixOS
   rebuild.
4. Land required owner and catalog commits and update clean main checkouts.
   Run `agents sync`; change permission only when requested or needed.
5. Verify the active ID, owner revision, and provider projection resolve to
   that published source. Unlanded or ambiguous authority blocks activation.

For catalog and projection mechanics, use `agents path agent-policy-reference`.
