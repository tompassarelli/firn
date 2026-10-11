# Importing existing Nix

To convert hand-written `.nix` to a Galileo module:

```bash
galileo import nix file.nix > default.gal
```

Review the output, then run `firn repo build` and `firn repo validate`.
