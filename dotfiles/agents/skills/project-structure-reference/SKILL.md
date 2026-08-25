---
name: project-structure-reference
description: >-
  Workflow-inventory, lifecycle, data-provenance, naming, checkpoint, handoff,
  and attribution reference for project-structure-distilled. Load only when
  that skill routes here through `agents path project-structure-reference`;
  this is not the trigger or minimum workflow for restructuring a project.
---

# Project structure reference

The distilled skill owns the layout decisions, safeguards, and completion
criteria. Use this reference for detailed inventories and examples.

## Workflow inventory

Inventory only concerns present in the project:

- authoritative source;
- acquired or immutable inputs;
- transformations and their code or configuration;
- generated artifacts and disposable scratch material;
- retained checkpoints;
- published results;
- externally stored or restricted data.

For each item, identify its producer, consumers, authority, lifecycle,
retrieval axis, scale, and retention need. A directory boundary is justified
when one of those differs materially. Metadata already carried reliably by a
manifest, database, artifact identity, or source control does not need to be
restated as hierarchy.

## Data provenance detail

When a project acquires or transforms data, useful acquisition facts can
include origin or durable identifier, acquisition context, checksum, license,
schema, and snapshot identity. Include only the facts that affect reacquisition,
verification, reuse, or interpretation. Large or restricted inputs can remain
outside Git when their immutable external identity is explicit.

A stage boundary represents a semantic or lifecycle change, not a conventional
folder name. Record the transform and its input relationship; a name such as
`raw` or `final` is not provenance. Each analysis or publication should identify
the canonical stage it consumes. Published claims may also need parameters and
environment information when those affect reproduction.

## Checkpoints and naming

Checkpoint value comes from expensive reruns, inspection, branching, recovery,
or handoff. Without one of those needs, recomputable intermediates are usually
disposable.

Naming follows repository and tool conventions for case, delimiters,
extensions, and spaces. Put a date, sequence, subject, location, machine,
model, or experiment first only when it is a genuine retrieval axis, and use a
sortable representation when sort order matters. Prefer meaningful artifact or
revision identity over `_final_final` and ad hoc `_vN`; explicit versions belong
to real versioned artifacts or protocols. Define project-local abbreviations a
newcomer could not infer.

Common data trees are examples rather than templates. Stage names should carry
project semantics, while ordinary Cargo, compiler, library, service, and system
projects retain their native layouts.

## Handoff detail

A handoff identifies authoritative source, immutable or external inputs,
generated and disposable material, retained and published outputs, and the
native rerun command. Existing Cargo, Nix, `just`, repository scripts, or an
orchestrator are preferable to a new runner. A real experiment may additionally
record input and code revision, parameters, output identity, and observations
needed to compare or repeat it.

## Provenance

This independently worded synthesis was adapted from MIT Broad Research
Communication Lab, “File Structure”; the source page is licensed CC BY-NC 4.0:
https://mitcommlab.mit.edu/broad/commkit/file-structure/
