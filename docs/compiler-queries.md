# Query the compiler instead of grep

For anything mechanical (what's the signature of X, what fields does record R have, who calls this, where is this declared), use the daemon-backed query tools — they answer in ~100ms warm and never go stale:

```bash
beagle-syntax FILE                      # structural delimiter check (--ledger for trace, --repair --emit-patch for auto-fix)
beagle-sig NAME FILE...                 # typed signature lookup
beagle-fields RECORD FILE...            # record fields, types, accessors
beagle-provides FILE                    # module exports
beagle-callers NAME FILE...             # call sites
beagle-impact NAME FILE...              # change impact: callers + transitive
beagle-expand FILE                      # show macro expansion
beagle-daemon status                    # confirm the warm cache is up
beagle-daemon start --watch .           # if not running
```

The daemon auto-starts on first edit via the PostToolUse hook, but `beagle-daemon status` at session start avoids cold-start delay.
