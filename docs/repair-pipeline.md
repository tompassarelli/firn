# Repair pipeline (when validate alone isn't enough)

`firn repo validate` catches most things in seconds. When a bug isn't pinned to one file or the validator says something's wrong but the fix isn't obvious, use the compiler's evidence-ranked queries before changing source:

```bash
beagle syntax path/to/source.bnix
beagle sig FUNCTION path/to/source.bnix
beagle callers FUNCTION path/to/source.bnix
beagle impact FUNCTION path/to/source.bnix
```

The pipeline combines six evidence layers (specfix-oracle 0.95, type-error + suggestion 0.90, type-error + fix-plan 0.85, trace + semantic agreement 0.80, semantic suspicion 0.65, blame 0.60) and ranks by confidence.

The native Firn routes are the repository oracle:

```bash
firn repo build
firn repo validate
```

Run the full `nix build` rung only when native build and validation cannot prove the relevant evaluation behavior.
