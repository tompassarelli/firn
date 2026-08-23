---
name: project-structure
description: >-
  Design or restructure project layouts so authoritative source, inputs,
  transformations, generated artifacts, scratch work, results, and handoff
  boundaries have clear lifecycles. Use when reorganizing directories or
  filenames, defining a data pipeline's immutable inputs and stages, making
  data-and-code work reproducible or discoverable, or documenting a layout and
  rerun path for handoff. Preserve native language and build conventions;
  apply data-stage and experiment rules only when those concerns exist.
---

# Project Structure

## Map the real workflow

- Read the repository instructions, manifests, documentation, existing layout,
  and native build or analysis commands before proposing a hierarchy.
- Inventory only the concerns that exist: authoritative source, acquired or
  immutable inputs, transformations, generated artifacts, retained
  checkpoints, scratch work, published results, and externally stored data.
- Trace each producer and consumer. Identify which input feeds downstream work,
  which outputs are reproducible or disposable, and which artifacts must be
  retained or published.
- Preserve repository-relative paths in code and documentation. Use an absolute
  path only for genuinely fixed external state, then make that dependency
  explicit rather than disguising it as project content.

## Choose the smallest useful hierarchy

- Add a boundary only when it separates authority, lifecycle, ownership,
  retrieval, scale, or a producer/consumer edge. Prefer existing repository
  conventions when they already express the distinction.
- Keep normal Cargo, compiler, library, service, and system layouts intact for
  ordinary software work. Do not create `data`, `raw`, `intermediate`, `final`,
  `results`, `scratch`, experiment logs, or a new runner when the project has no
  corresponding concern.
- Treat common project trees as examples, never templates. Stage names should
  describe the project's semantics; they need not be `raw`, `intermediate`, and
  `final`.
- Keep a checkpoint only when rerun cost, inspection, branching, recovery, or
  handoff justifies it. Avoid hierarchy that merely restates metadata already
  carried reliably by a manifest, database, artifact identity, or source
  control.

## Make data lifecycles reproducible

Apply this section only when the project acquires, transforms, analyzes, or
publishes data.

- Preserve acquired inputs byte-for-byte or preserve an immutable external
  identity for them. Do not assume large or restricted inputs belong in Git.
- Record enough provenance to reacquire or verify an input: origin or durable
  identifier, acquisition context, and checksum, license, schema, or snapshot
  identity when they affect reuse or interpretation.
- Express canonical transformations in versioned code or configuration. Keep
  manual edits, ad hoc renames, and shell-history-only steps out of the
  authoritative pipeline.
- Separate stages when their semantics or lifecycle differ, and declare the
  canonical stage consumed by each analysis or publication step. A folder name
  alone is not provenance; retain the transform and its input relationship.
- Make published results traceable to their inputs, transformation revision,
  parameters, and environment to the degree needed to reproduce the claim.

## Name for retrieval

- Follow repository and tool conventions for case, delimiters, extensions, and
  spaces. Do not introduce a universal no-spaces or delimiter rule.
- Put a date, sequence, subject, location, machine, model, or experiment first
  only when it is a real retrieval axis. Use sortable date and sequence forms
  when sorting by them matters.
- Prefer meaningful artifact or revision identities over `_final_final` names
  and manual `_vN` suffixes. Use explicit versions only when the project has a
  real versioned artifact or protocol.
- Keep names concise and unambiguous in their full path. Define project-local
  abbreviations when a newcomer could not infer them.

## Leave an executable handoff

- Migrate every affected import, path consumer, build rule, test, script, and
  document when moving content. A tidy tree with broken consumers is not an
  improvement.
- Document the authoritative source, immutable or external inputs, generated
  and disposable material, retained outputs, and the native rerun path. Reuse
  Cargo, Nix, `just`, repository scripts, or the existing orchestrator; do not
  require a Makefile.
- For actual experiments, record the input and code revision, parameters,
  output identity, and observations needed to compare or repeat the run. Do not
  impose experiment ceremony on ordinary development.

## Completion

- Existing workflows still run and all moved references are migrated.
- Each real artifact has an evident authority and lifecycle.
- Data provenance and transformation edges are reconstructible where data is
  present.
- Derived, disposable, retained, and published outputs cannot be confused where
  those categories differ.
- A newcomer can locate the relevant inputs, code, outputs, and rerun path.
- The hierarchy contains no concern invented solely by this skill.

## Provenance

This independently worded synthesis was adapted from MIT Broad Research
Communication Lab, “File Structure”;
the cited source page is licensed CC BY-NC 4.0:
https://mitcommlab.mit.edu/broad/commkit/file-structure/
