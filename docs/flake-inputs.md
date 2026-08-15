# Flake inputs (codegen)

Modules that need a flake input declare it **co-located** in their `default.bnix` via `:flake-inputs`. `firn repo build` collects all `:flake-inputs` from every module and splices them into `flake.bnix` between markers. **Never hand-edit the generated sections in `flake.bnix`** — the next `firn repo build` overwrites them.

Adding a module with a flake input = add the `:flake-inputs` clause. Removing = delete it. No flake.bnix edits needed.

### Module-side

```clojure
(nix/module [config lib pkgs inputs ...]
  {:flake-inputs
    {:walker {:url "github:abenz1267/walker"
              :inputs.elephant.follows "elephant"}
     :elephant {:url "github:abenz1267/elephant/..."}}
   :tags [desktop]
   :options...
   :config...})
```

Each key in `:flake-inputs` is an input name; the value is a map of flake input attributes (`:url`, `:inputs.X.follows`, `:flake`). A module may declare multiple inputs. Inputs with dependencies between them (walker → elephant) are co-declared in the owning module.

### What gets generated

`firn repo build` splices into 6 marker-delimited sections of `flake.bnix`:
1. `:inputs` map — the input declarations
2. Outputs arg list — binding names
3. NixOS `specialArgs` — `:inputs` map entries
4. HM `extraSpecialArgs` — same entries
5. Darwin `specialArgs` — same entries
6. Darwin HM `extraSpecialArgs` — same entries

Markers look like: `;; --- GENERATED MODULE INPUTS (do not edit) ---`

### Conflict detection

Two modules declaring the same input name with different URLs → hard error. Same name + same URL → silently merged (the first module wins for bookkeeping).

### Debugging

```bash
firn flake-input resolve show    # list collected inputs + source modules
firn flake-input resolve emit    # splice into flake.bnix
```

### What stays hand-authored

Infrastructure inputs (nixpkgs, home-manager, nix-darwin, stylix, sops-nix) and overlay-consumed inputs (kanata-git, glide) remain hand-authored in `flake.bnix` above the markers.
