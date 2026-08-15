# Repair pipeline (when validate alone isn't enough)

`firn repo validate` catches most things in seconds. When a bug isn't pinned to one file or the validator says something's wrong but the fix isn't obvious, use the evidence-ranked repair tools. They take a **verify script** as argument — the oracle that decides whether a speculative fix actually worked. This repo ships one:

```bash
# Confidence-ranked repair queue (does not modify files):
beagle-repair . scripts/firn-verify

# Auto-apply fixes above the confidence threshold, then re-verify:
beagle-repair . scripts/firn-verify --auto --threshold 0.85

# Emit a patch you can review before applying:
beagle-repair . scripts/firn-verify --emit-patch
```

The pipeline combines six evidence layers (specfix-oracle 0.95, type-error + suggestion 0.90, type-error + fix-plan 0.85, trace + semantic agreement 0.80, semantic suspicion 0.65, blame 0.60) and ranks by confidence.

When stuck on a specific function or after a verify failure:

```bash
beagle-trace . scripts/firn-verify --focus FN-NAME      # execution trace
beagle-cascade . scripts/firn-verify --from-failures    # cross-file impact of the failure
beagle-blame . scripts/firn-verify                      # semantic blame: which form is responsible
beagle-specfix . scripts/firn-verify                    # speculative fix verified against oracle
```

`scripts/firn-verify` runs Rungs 1 + 2 (firn-build + firn-validate). Pass `--eval` to it for the heavier Rung 3 (full `nix build`) — only worth it when the validator can't see the bug.
