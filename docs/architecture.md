# Architecture

- **Module** = atom. One package or service. Lives in
  `modules/<name>/default.gal` (with a regenerated `default.nix`
  sibling).
- **Tags** = composition. A module joins a tag with `<module> is tagged
  <tag>` (default-on) or `<module> can opt into <tag>` in its `.gal`. A
  host's `_generated-enables.gal` enables tags and edits them; the resolver
  unions per-tag memberships and subtracts the host's disables. See
  [TAGS.md](TAGS.md).
- **Host** = leaf. `hosts/<host>/configuration.gal` sets options and may
  turn single modules on or off; `hosts/<host>/_generated-enables.gal`
  picks the tag set.

`firn rebuild` provisionally refreshes local harness inputs, then runs
`firn repo build` → `firn repo validate` → host-closure build → verified lock commit →
system switch → tag. Modules auto-discover via the flake's dynamic `imports` — adding a
module means creating the directory + `.gal`, running `firn repo build`,
and `git add`-ing both files. No flake edits.

```
.
├── flake.gal          source-of-truth flake (Galileo)
├── flake.nix          generated
├── modules/  hosts/   .gal source (+ generated .nix siblings)
├── native/            Firn CLI commands, policies and workflow controllers (Beagle/JS `.bjs`)
├── template/          starting point for `nix flake init -t`
├── dotfiles/  secrets/  assets/
└── docs/              TAGS.md — composition model
```

Both `.gal` and `.nix` are committed because the flake reads from the
git tree. **Edit the `.gal`** — `firn repo build` overwrites direct `.nix`
edits.

North is promoted independently and reached through `~/.local/share/north/bin/north`;
Firn owns only the stable launcher, guard wiring, and delivery-liveness entry.
