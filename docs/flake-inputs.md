# Flake inputs (codegen)

A module that needs a flake input declares it in its `default.gal`:

```
walker needs flake input "walker" from "github:abenz1267/walker"
walker needs flake input "elephant" from "github:abenz1267/elephant/..."
```

`firn/tags` derives `?name flake input url ?url` from these facts, with at most one url per name. `flake.gal` emits every generated section of `flake.nix` from that relation: the `inputs` entries, `outputs`' formals, and the four `inputs` records in NixOS, home-manager, darwin and darwin home-manager `specialArgs`. Follows are facts in `flake.gal`, for example `flake input "walker" follows "elephant" from "elephant"`.

Adding a module with a flake input means adding its `needs flake input` fact; removing it means deleting the fact. `flake.gal` needs no edit.

### Conflict detection

Two modules declaring the same input name with different URLs fail `galileo build`, which names both modules and writes no `flake.nix`. The same name with the same URL is merged; the summary names the first module.

### Commands

```bash
firn flake-input resolve emit    # galileo build of flake.gal, then list inputs and their modules
```

### What stays hand-authored

Infrastructure inputs (nixpkgs, home-manager, nix-darwin, stylix, sops-nix) and overlay-consumed inputs (kanata-git, glide) stay written out in `flake.gal`.
