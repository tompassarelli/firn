# Racket / Beagle: one pinned racket, never stale bytecode — MANDATORY

The system racket (nixos-config) and a Beagle project's flake-pinned racket are
DIFFERENT versions (e.g. system 9.2 vs flake 9.1). Racket `.zo` bytecode is
version-specific: load 9.1-compiled `.zo` under 9.2 and racket dies with
`body of .../raco.rkt`. This is the single most recurring footgun here.

**Rules (non-negotiable):**
1. **Never run bare `racket`/`raco`** in a Beagle/Racket project. Always
   `source bin/_beagle-racket` then use `$RACKET` / `$RACO`, or `direnv exec . raco …`.
   `_beagle-racket` resolves the flake-pinned racket — and in a **git worktree**
   (no allowed `.direnv`) falls back to the canonical `~/code/beagle` pin, so the
   version is consistent everywhere. Source it; do not bypass it.
2. **After ANY `.rkt` edit, rebuild before testing**: `"$RACO" make <file>` (via
   the pinned racket). Stale `.zo` runs old code and makes bugs look unfixable —
   if a fix "doesn't take", suspect stale bytecode first.
3. **Worktrees of a flake project**: collection links + `.zo` are per-racket; keep
   the SAME pinned racket for build AND test in the worktree (source
   `bin/_beagle-racket`). Never mix the worktree's bare racket with the main pin.

The `~/code/nixos-config/dotfiles/agents/hooks/racket-build-guard.sh` PostToolUse
hook enforces this: on any `.rkt` edit it injects a structured PostToolUse
warning into agent context if the ambient racket ≠ the project pin, or if the
edited file's `.zo` is now stale. The advisory exits 0 so a real diagnostic is
not mislabeled as a generic hook failure. Heed it — don't build/test until it's
clean.
