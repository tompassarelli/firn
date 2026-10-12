# Tags — composition model

Tags are the **only** composition primitive in firn. A module joins zero or
more tags with facts in its `.gal` source; a host enables tags with facts in
its `_generated-enables.gal`; the resolver computes the active module set by
union-then-subtract. The vocabulary is Galileo's `firn/tags` library, which
every source loads with `use firn/tags`.

The legacy `myConfig.bundles.*` pattern (per-bundle sub-options + `mkDefault`
proxies) has been removed; both the `bundles/` directory and the `bundle` CLI
node are gone.

---

## TL;DR

```
# modules/firefox/default.gal — module joins a tag
firefox is tagged browsers

# modules/chrome/default.gal — module joins a tag only when a host adds it
chrome can opt into browsers

# hosts/whiterabbit/_generated-enables.gal — host enables tags and edits them
whiterabbit enables desktop
whiterabbit adds river to desktop
whiterabbit drops mako from desktop
whiterabbit disables blender
```

Resolution: every module tagged with an enabled tag is on, unless the host
drops it from that tag or disables it. A module that can only opt into a tag
joins when the host adds it to that tag.

---

## Module-side facts

All are optional; a module with no tags is reachable only through a host's
`turns on` fact or another module's `imports`.

- `<module> is tagged <tag>`: default-on membership. When a host enables the
  tag, the module is on unless the host drops or disables it.
- `<module> can opt into <tag>`: opt-in membership. The module joins only when
  the host states `<host> adds <module> to <tag>`. Use it for "this module
  makes sense for tag T, but not every T host should get it", such as a second
  browser under `browsers`.
- `<module> supports <platform>`: on a platform that does not allow every
  module (`darwin`), only supported modules can be enabled. `config/tags.gal`
  declares the tags and platforms.

Tags are flat, kebab-case and declared once in `config/tags.gal` as
`<tag> is a Tag`.

A tag can also set a value for a module it enabled by default:
`<tag> sets <path> to <value> for <module>`. The host then gets that value; a
module added with `adds` does not.

---

## Host-side facts

`hosts/<host>/_generated-enables.gal` holds the host's tag facts; `firn tag`
and `firn module` edit it.

- `<host> enables <tag>`: turn on the tag's default-on members.
- `<host> drops <module> from <tag>`: remove the module from this tag's
  contribution only; another enabled tag that includes it still counts.
- `<host> adds <module> to <tag>`: add an opt-in member. The checker rejects it
  unless the module `can opt into` that tag and is supported on the host.
- `<host> disables <module>`: off no matter which tags would pull it in.

`hosts/<host>/configuration.gal` may also state `<host> turns on <module>` or
`<host> turns off <module>`. `turns on` enables a module with no tag;
`turns off` wins over every tag. A host may not state both for one module.

---

## Resolution

```
enabled by default through T := host enables T, module is tagged T,
                                 and host does not drop module from T
enabled by T                  := enabled by default through T,
                                 or host enables T, adds module to T,
                                 and module can opt into T
tag-enabled                   := enabled by some T, supported on the host,
                                 not disabled and not turned off
enabled                       := tag-enabled, or turned on
```

Galileo's `firn/tags` library states these as rules; `galileo build` writes
the result to `hosts/<host>/_generated-enables.nix` as
`myConfig.modules.<module>.enable` settings.

---

## Worked examples

1. **Enable a tag.** `whiterabbit enables browsers` turns on every module
   tagged `browsers`.
2. **Drop one member.** Add `whiterabbit drops firefox from browsers`: firefox
   is off unless another enabled tag also includes it.
3. **Opt in.** `chrome can opt into browsers` keeps chrome off until
   `whiterabbit adds chrome to browsers`. Adding it to a tag it cannot opt into
   fails the check.
4. **Hard disable.** `whiterabbit disables piper` keeps piper off whatever tags
   are enabled.

---

## Editing host tags from the CLI

```bash
firn tag enable  <tag>            # add "<host> enables <tag>"
firn tag disable <tag>            # remove it
firn tag opt-in  <tag>+<module>   # add "<host> adds <module> to <tag>"
firn tag opt-out <tag>+<module>   # add "<host> drops <module> from <tag>"
firn tag status <host>            # the host's tag facts and resolved modules

firn module enable  <module>      # remove "<host> disables <module>"
firn module disable <module>      # add "<host> disables <module>"
```

`firn tag resolve <host>` prints which tag enabled each module; use it when
"why is module X enabled?" is not obvious. `firn repo validate` runs
`galileo check`, which enforces the requirements in `firn/tags`.
