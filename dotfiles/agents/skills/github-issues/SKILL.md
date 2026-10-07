---
name: github-issues
description: >-
  Create or edit GitHub issues, including issue labels, using the repository's existing ticket and tagging conventions.
---

# GitHub issues

Issue creation requires operator authorization, including an explicit request
for agenda tracking or task decomposition into tickets. A discovery during
implementation does not itself authorize another ticket.

Before creating or editing an issue, resolve the exact repository and read its
applicable instructions, issue templates and any issue-tracking guidance.
Fetch the live label catalog with descriptions and inspect a few comparable
existing issues, including recent ones. Reuse the repository's conventions;
do not invent labels or a new taxonomy to fill a perceived gap.

Choose labels from the issue's actual scope and the established conventions:
issue type, relevant theme(s), and priority/status dimensions where applicable.
Match comparable issues' tagging completeness at creation, passing the labels
in the create operation instead of leaving an untagged ticket for later.
Do not infer priority from recency, or completion/evidence from a passing
component check. When no existing label fits a dimension, omit that dimension;
a missing owner decision matters only when it blocks the requested change.

When repairing labels, preserve legitimate existing labels and change only
missing or demonstrably incorrect ones. Keep issue body, acceptance checklist,
status and open/closed state intact unless the requested work covers them.
For a batch, bound it to the named tickets or clearly evidenced same-session
omissions; issue metadata repair does not count as ticket completion.

After each create/edit operation, read the issue back from GitHub and verify
the intended labels and requested content. Report the issue links and actual
changes. Read-only issue lookup or reporting needs no metadata mutation.
