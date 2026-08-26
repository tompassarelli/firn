---
name: project-structure-distilled
description: >-
  Design or restructure project layouts so authoritative source, inputs,
  transformations, generated artifacts, scratch work, results, and handoff
  boundaries have clear lifecycles. Use when reorganizing directories or
  filenames, defining a data pipeline's immutable inputs and stages, making
  data-and-code work reproducible or discoverable, or documenting a layout and
  rerun path for handoff. Preserve native language and build conventions;
  apply data-stage and experiment rules only when those concerns exist.
---

# Project structure

Read repository authority and trace real producers, consumers, lifecycles,
ownership, retrieval, scale, and external state before choosing a hierarchy.

Add boundaries only for real distinctions. Preserve native layouts; do not
invent data stages, results, scratch, experiments, or runners. Use relative
paths except for explicit external state. Keep only justified checkpoints.

For real data, preserve bytes or immutable identity, needed provenance, and
versioned transforms; trace results to inputs and material run context. Do not
impose data or experiment ceremony on ordinary software.

Migrate every consumer, build rule, test, script, and document. Leave the native
rerun path and distinguish authority and lifecycle.

Complete when workflows run, authority and applicable provenance are clear,
and newcomers can locate inputs, code, outputs, and rerun path. Route unresolved
detail to the reference skill only for an explicit request or a named unresolved
question.
