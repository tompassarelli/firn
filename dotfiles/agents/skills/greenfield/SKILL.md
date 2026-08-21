---
name: greenfield
description: >-
  Choose current technology for new work without importing a stale model or a
  compromised package. Use when starting a new project, selecting a framework,
  runtime, or library, adding a first dependency, or answering "what should we
  use for X".
---

# Greenfield

New work gets current technology. Not what you remember — what is actually
current, verified now.

## Research before recommending

Your training data is stale by construction. A recommendation drawn from
memory is a claim about the past presented as a claim about the present.

Before naming any library, framework, or runtime for new work:

- look up its current release and its release date;
- check whether the thing you remember as current has been superseded,
  renamed, deprecated, or absorbed;
- find what people are actually choosing now, not what was chosen when your
  data was collected.

State when you checked. "As of today's lookup" is a real qualifier; "I believe
the current version is" is not.

## Show the frontier, not one option

Name the leading options and what separates them, then recommend one. A single
suggestion hides whether you surveyed or just recalled. If none of the options
are actually current, say so and go find the ones that are.

## Version selection — the aging rule

Prefer the current stable release, with one exception:

**Do not adopt a package version published in the last ~14 days.**

Supply-chain compromises — a hijacked maintainer account, a malicious
post-install script, a typosquat — are usually caught within days of
publication. The waiting period is the defense, and it costs almost nothing on
a greenfield project.

Take a fresh release only when it fixes a security issue you are actually
exposed to, or the project genuinely cannot proceed without it. Say which.

## Before adding any dependency

- **Is it real?** Check the exact name against the official registry. Typosquats
  differ by one character and rank well in search.
- **Is it maintained?** Recent commits, responsive issues, more than one
  maintainer where it matters.
- **Is it used?** Download counts and dependents distinguish a real library
  from an abandoned experiment with a good name.
- **What does it pull in?** A small package with sixty transitive dependencies
  is a large package.
- **What is its license?** Check before use, not after.
- **Does it need install scripts or network access at build time?** Both are
  worth a second look.

## Choosing what to own

Cutting edge does not mean maximal dependencies. Prefer an owned
implementation when the capability is small, central, and differentiating.
Prefer a dependency when it is commodity work whose maintenance and security
burden exceeds the value of owning it.

Neither "build it ourselves" nor "there's a package for that" is a default.

## What this is not

This is licence to pick modern technology, not to pick novelty. A brand-new
framework with no production users is a research bet — take it deliberately
and say that you are, rather than smuggling it in as the obvious choice.
