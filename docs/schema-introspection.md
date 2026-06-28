# Schema introspection

Before adding/changing options, query the schema:

```bash
beagle-schema services.openssh.enable               # exact lookup: type, default, enum
beagle-schema --children services.openssh           # list all sub-options under a prefix
beagle-schema --search ssh                          # fuzzy substring search
beagle-schema --json services.openssh.enable        # machine-readable
```

This is the right way to answer "does option X exist?" or "what type does X want?" — far better than `grep schema.json`.
