# Discovering platform compatibility

`firn platform list` answers "which modules work on darwin?" by cross-referencing each module's referenced option paths against both the NixOS and darwin schema caches:

```bash
firn platform list all          # full matrix
firn platform list darwin       # only darwin-compatible modules
firn platform list linux        # NixOS-only
firn platform show <name>       # single module, with blocking paths
firn platform safelist          # safelist snippet for flake.bnix
```

Pre-req: `./scripts/firn-extract-schema` and `./scripts/firn-extract-schema --darwin` (separate caches: `.beagle-cache/schema.json` and `.beagle-cache/schema-darwin.json`). `firn repo doctor` warns when the darwin cache is stale.

**Limitation**: this is a schema-compatibility check. Pure-pkg modules whose only setter is `environment.systemPackages` always pass — the option path exists on darwin even when the package has no darwin build. Use `darwin-rebuild build` to verify.
