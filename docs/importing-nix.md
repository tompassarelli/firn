# Importing existing Nix

If the user has hand-written `.nix` and wants to convert to beagle/nix:

```bash
beagle-import-nix file.nix > file.bnix
```

Built on rnix-parser (handles 100% of nixpkgs). Output may need manual adjustment to use beagle/nix forms. **Note:** `beagle-import-nix` refuses `flake-file` forms — the project flake must be migrated by hand.
