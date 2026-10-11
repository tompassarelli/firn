# Schema introspection

Before adding or changing options, ask the schema:

```bash
galileo schema explain services.openssh.enable      # path, type and default
firn schema explain <path-or-validator-error>       # the same through firn
```

This answers "does option X exist?" and "what type does X want?" better than
grepping `schema.json`.
