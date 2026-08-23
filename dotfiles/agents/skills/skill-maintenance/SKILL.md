---
name: skill-maintenance
description: >-
  Convert explicit, repeated, or strongly emphasized operator feedback into
  scoped durable agent policy. Use for corrections such as “remember this,”
  “make this a rule,” “do not make me repeat this,” recurring failures, or
  important feedback that should refine an existing AGENTS.md rule or skill.
---

# Skill maintenance

Own the feedback-to-policy ratchet. Compile reusable normative feedback into
the narrowest authoritative policy without turning skills into a transcript or
calling a draft “remembered.”

Use `agent-policy` for ownership, placement, registration, projection, and
activation mechanics. This skill owns deciding what lesson should become
durable and how its semantics should ratchet.

## Admit durable feedback

Treat feedback as a ratchet candidate when at least one is true:

- the operator explicitly asks for a lasting rule or says to remember it;
- the same correction or failure recurs and has one stable reusable lesson; or
- strongly emphasized feedback states an important operating constraint that
  should govern future matching situations.

Intensity raises priority, not scope. Derive scope from the semantic rule and
its trigger, never from the harshness of its delivery.

Do not mutate durable policy for an incident-only instruction, a current-task
preference, a personal fact, an explanation without a normative rule, or
frustration whose reusable meaning is unclear. Honor a one-off instruction in
the current task. Treat episodic facts or preferences as memory only when the
governing memory system and the operator's request justify that; policy says
what agents must do, while memory preserves useful facts.

## Extract the semantic rule

Rewrite the feedback as:

```text
Trigger:
Rule:
Scope:
Compliant move:
Exceptions or escalation:
```

Preserve the operator's intended force and concrete boundary. Remove insults,
emotional chronology, incident history, dates, and self-justification from the
policy text. Put provenance in the commit message or private continuity record,
not in the durable rule.

If the reusable rule cannot be stated without the episode, keep it episodic.
When recurrence suggests a rule but its scope remains ambiguous, inspect the
prior cases before broadening it.

## Ratchet the existing owner

1. Use `agents status`, `agents inspect <id>`, and `agents path <id>` plus
   repository search to find the current owning policy.
2. Amend that owner first. Remove superseded, conflicting, or duplicate wording
   in the same change so policy ratchets instead of accumulating archaeology.
3. Keep `AGENTS.md` for universal or directory-wide boundaries that must govern
   every matching action.
4. Use one coherent skill for a triggerable workflow. Do not create aliases,
   tiny one-rule skills, or a second owner merely to preserve the new wording.
5. Use a hook only when deterministic enforcement is required and mechanically
   decidable. Strong feedback alone never justifies a hook; route justified hook
   work through `guard-authoring`.
6. Create a new skill only when no coherent owner exists and the rule forms a
   reusable workflow with reliable triggers.

Never edit `~/.agents`, `~/.codex`, or another projection. Work in the owning
repository's admitted lane and let `agent-policy` govern registration and the
live projection path.

## Validate the ratchet blind

Test the semantic boundary, not a memorized phrase:

- Give a fresh agent the candidate policy, raw task fixture, and ordinary
  repository context without the intended answer or evaluator rubric.
- Run at least one positive case where the durable trigger applies and one
  negative control where similar language is explicitly episodic or out of
  scope.
- Keep cases isolated so one run cannot observe another run's edits or output.
- Check that the positive case changes the correct existing owner, removes the
  superseded opposite rule, and follows the new compliant move.
- Check that the negative case does not manufacture a skill, `AGENTS.md` rule,
  hook, or memory.

Also run the owning skill's structural validator and nearest existing
registration or behavior fixture. A passing wording check alone is not proof of
the intended behavior.

## Publish before claiming retention

Land the owning change through its normal publication path, fast-forward the
clean authority checkout, run `agents sync`, activate the owning UnitId, and
prove the current generation resolves to the landed authority. Use `agents
status`, `agents inspect <id>`, and `agents path <id>` as directed by
`agent-policy`.

Do not say the feedback is remembered, retained, or now policy while it exists
only in a draft, lane, candidate commit, test fixture, or inactive catalog row.
The claim becomes true only after publication, activation, and current-
generation proof all succeed.
