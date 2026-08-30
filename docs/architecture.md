# Architecture

- **Module** = atom. One package or service. Lives in
  `modules/<name>/default.bnix` (with a regenerated `default.nix`
  sibling).
- **Tags** = composition. A module joins a tag via `:tags` (default-on)
  or `:tags-opt-in` (opt-in) in its `.bnix`. Hosts declare a tag
  selection; the resolver unions per-tag memberships and subtracts a
  per-host disabled list. See [TAGS.md](TAGS.md).
- **Host** = leaf. `hosts/<host>/configuration.bnix` sets options;
  `hosts/<host>/enabled-tags.bnix` picks the tag set.

`firn rebuild` provisionally refreshes local harness inputs, then runs
`firn repo build` → `firn repo validate` → host-closure build → verified lock commit →
system switch → tag. Modules auto-discover via the flake's dynamic `imports` — adding a
module means creating the directory + `.bnix`, running `firn repo build`,
and `git add`-ing both files. No flake edits.

```
.
├── flake.bnix         source-of-truth flake (#lang beagle/nix)
├── flake.nix          generated
├── modules/  hosts/    .bnix source (+ generated .nix siblings)
├── scripts/           retained Beagle build-time repository builder
├── native/            typed Firn commands, policies, and workflow controllers
├── template/          starting point for `nix flake init -t`
├── dotfiles/  secrets/  assets/
├── docs/              TAGS.md — composition model
└── tests/             validator regression fixtures (.bnix)
```

Both `.bnix` and `.nix` are committed because the flake reads from the
git tree. **Edit the `.bnix`** — `firn repo build` overwrites direct `.nix`
edits.

The `north-coordinator` module launches North's live out-of-store coordinator,
which hosts the sealed JVM Store selected by North in-process.
