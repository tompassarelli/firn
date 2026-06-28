# Diagnosing schema errors

When the validator reports an unknown option, type mismatch, or you're about to write a new `(set …)`, use `firn schema explain` instead of digging through `schema.json` by hand:

```bash
firn schema explain services.openssh.enable                     # bare option path
firn schema explain "modules/foo.bnix:6:7: unknown option services.opensh.enable"   # paste a validator error directly
```

Output: type, declarations (links to upstream NixOS module sources), and every `.bnix` file in this repo that references the path. If the path doesn't exist, prints did-you-mean candidates.
