---
name: repo-safety-distilled
description: >-
  Edit and publish ~/code repositories through owned worktrees, enumerated staging, and safe-push; preserve main checkouts, pins, and peer work.
---

# Repository safety

Work in `~/code/<project>/worktrees/<slug>`. Main checkouts are human/launch
state; pins are immutable. Never edit, stash, reset, clean, or commit dirty
main. Use the sanctioned rescue workflow when relocation is required.

Keep build output inside its lane, including each Rust target directory;
use an explicit temporary target only when output must live elsewhere.
Never place build-output directories in a project container.

Stage named paths only. Prohibited shortcuts include `git add -A`,
`git add -u`, `git add .`, and `git commit -a`. Let commit hooks finish,
publish separately with `safe-push --to main`, then fast-forward clean main.

Preserve roots, Git metadata, transcripts, live pins, and peer lanes. Only a
lane's owner or accountable parent may retire it after its work is settled;
clean status or merged ancestry does not prove release. Unknown ownership
preserves the lane.

Signal only owned processes by exact PID or unique scoped pattern. Never expose
credentials; authenticated use and scoped transfer follow global policy.

A guard denial supplies boundary information. Take its sanctioned route;
do not bypass a secret finding, private-to-public exposure, uncertain
destructive target, or unresolved live consumer.

For lane creation, rescue, pin retirement, and scoped operations, use
`agents path repo-safety-reference`.
