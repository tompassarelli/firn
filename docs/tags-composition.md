# Tags (composition model)

Tags are the **only** way modules get composed. A module states which tags it
joins; a host enables tags and edits them; the resolver unions the memberships
and subtracts the host's disables. This replaced the legacy
`myConfig.bundles.*` pattern, which has been fully removed.

### Module-side: `modules/<name>/default.gal`

```
use firn/tags

firefox is a Module
firefox is tagged browsers

nix module
  arguments: config, lib, pkgs, ...
  option myConfig.modules.firefox.enable: enable "Enable Firefox browser"
  imports: [./firefox.nix]
```

- `<module> is tagged <tag>`: default-on membership.
- `<module> can opt into <tag>`: joins only when a host adds it to the tag.
- `<tag> sets <path> to <value> for <module>`: a value applied when that tag
  enabled the module by default.

Tag facts live in the `.gal` source only; the generated `.nix` holds the
module itself.

### Host-side: `hosts/<host>/_generated-enables.gal`

```
use firn/tags

whiterabbit is a Host
whiterabbit runs linux
whiterabbit enables desktop
whiterabbit drops mako from desktop
whiterabbit adds river to desktop
whiterabbit disables blender
```

`hosts/<host>/configuration.gal` may also state `turns on` or `turns off` for
one module.

### Tooling

```bash
firn tag list all                   # tag universe
firn tag show steam                 # one module's tags and opt-in tags
firn tag filter gpu-required        # all modules with that tag
firn tag resolve <host>             # the active module set and which tag pulled each in
firn tag index stdout               # jsonl to stdout (pipe into jq/fzf)
```

**Full reference**: [`docs/TAGS.md`](TAGS.md): host facts, resolution and
worked examples.
