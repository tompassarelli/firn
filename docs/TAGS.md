# Tags — composition model

Tags are the **only** composition primitive in firn. A module joins zero or
more tags by declaring them in its `.bnix` source; a host enables a list of
tags; the resolver computes the active module set by union-then-subtract.

The legacy `myConfig.bundles.*` pattern (per-bundle sub-options + `mkDefault`
proxies) has been removed — both the `bundles/` directory and the `bundle` CLI
node are gone. The audit that drove the schema decisions still lives at the
bottom of this document for historical context.

---

## TL;DR

```clojure
;; modules/firefox/default.bnix — module joins tags
:tags [browsers gui-only]
:tag-overrides {browsers {:myConfig.modules.firefox.default true}}

;; hosts/whiterabbit/enabled-tags.bnix — host enables tags
{:enabled  [terminal
            [browsers -gjoa]
            [theming -nerd-fonts]]
 :disabled [piper]}
```

Resolution: every module that declares a tag in `:tags` is enabled when the
host enables that tag, unless the host writes `-<module>` in that tag's edit
list or lists the module in `:disabled`. Modules with `:tags-opt-in` only join
when the host writes `+<module>` in a matching tag.

---

## Module-side shape

`modules/<name>/default.bnix` may carry three tag-related clauses. All three are
optional; a module with no tags is reachable only via direct host wiring or via
another module's `imports`.

```clojure
#lang beagle/nix
(ns default)

(nix/module [config lib pkgs ...]
  {:options.myConfig.modules.firefox.enable
    (lib.mkEnableOption "Enable Firefox browser")

   ;; ---- TAG MEMBERSHIP ----
   :tags        [browsers gui-only]              ;; default-on memberships
   :tags-opt-in [headless-ok]                    ;; opt-in-only memberships
   :tag-overrides                                ;; per-tag value-overrides
     {browsers {:myConfig.modules.firefox.default true}}

   :config
     (lib.mkIf config.myConfig.modules.firefox.enable
       { ;; package + service wiring …
        })})
```

### `:tags`

A vector of bare symbols. Each entry is a tag this module joins by default.
When a host enables one of these tags, the module is enabled — unless the host
explicitly writes `-firefox` in that tag's edit list or lists `firefox` in
`:disabled`.

Naming convention: kebab-case, no namespace prefix. Tags are flat; there is no
hierarchy.

### `:tags-opt-in`

Same shape as `:tags`, but the membership only activates when the host writes
`+firefox` in the tag's edit list. This is for "this module makes sense for tag
T but I don't want every T host to get it by default" — e.g. a beta browser
under `browsers`, or a heavy LSP variant under `dev`.

Omit the clause when empty. Do not write `:tags-opt-in []`.

### `:tag-overrides`

A map keyed by tag-symbol. Each value is an attrset of `option-path => value`
pairs that should be applied (as `mkDefault`) when the module is enabled
**because of that tag**. The audit found 9 cases that need this:

- 8 in `bundles/browsers/default.bnix` — every browser module exports a
  `.default` bool (mark-as-default-browser) and the bundle proxied a
  `<browser>.default` slot through. Under the new model, the `firefox` module
  declares `:tag-overrides {browsers {:myConfig.modules.firefox.default true}}`
  and the resolver sets `firefox.default = true` whenever `browsers` is the
  reason firefox is on.
- 1 in `bundles/theming/default.bnix` — `stylix.chosenTheme` is a string-enum
  value-override, modelled the same way.

The remaining 132 mkDefault hits in the legacy bundles are pure enable-wiring
and collapse into plain `:tags` membership — no override needed.

Overrides apply only when the tag is the *default-on* reason for the module
being active. A module pulled in via `+name` does **not** get the override.
This keeps "I opted in manually" semantically distinct from "the tag claimed
me."

---

## Host-side shape

`hosts/<host>/enabled-tags.bnix`:

```clojure
#lang beagle/nix
(ns enabled-tags)

{:enabled
  [terminal                                            ;; bare = defaults, no edits
   [browsers -gjoa +qutebrowser-experimental]          ;; vector = edits applied
   [theming -nerd-fonts]
   dev]
 :disabled [piper auto-upgrade]}
```

### `:enabled`

A vector of entries. Each entry is either:

- A **bare tag symbol** (`terminal`, `dev`) — enable the tag with no edits.
  Every module that lists this tag in `:tags` is activated.
- A **vector** `[<tag> <flag>…]` — enable the tag with per-tag edits. Each flag
  is a symbol prefixed `-` or `+`:
  - `-mname` removes `mname` from this tag's default-on set. Scoped to this
    tag — if `mname` is also pulled in by another enabled tag, that one still
    counts. To kill the module everywhere, put it in `:disabled`.
  - `+mname` adds `mname` to this tag, but only if `mname`'s `:tags-opt-in`
    list includes this tag. Otherwise the validator errors out.

### `:disabled`

A vector of module names. Applied **after** the union. A module here is off no
matter how many tags would activate it. Use for "I never want this module on
this machine," independent of tag mix.

---

## Resolution algorithm

```
active := union over each enabled-tag T of (
  defaults := { m | T ∈ m.:tags }
  minuses  := { x | -x ∈ T's edit-flags }
  pluses   := { x | +x ∈ T's edit-flags AND T ∈ x.:tags-opt-in }
  (defaults \ minuses) ∪ pluses
)
enabled-modules := active \ host.:disabled
```

Notes:

- **Per-tag minus.** `-firefox` under `browsers` only removes firefox from
  browsers' contribution; if `gui-only` also lists firefox, firefox stays on.
- **Validated plus.** `+qutebrowser-experimental` under `browsers` fails the
  validator if the `qutebrowser-experimental` module doesn't list `browsers`
  in `:tags-opt-in`.
- **Disabled is absolute.** `:disabled` wins over every tag, opt-in or
  otherwise.

For each active module M, the resolver also walks each tag T where M ∈ T's
defaults (not pluses), and applies any `M.:tag-overrides[T]` entries as
`mkDefault` on M's options. The host's own settings beat `mkDefault`, so any
explicit value the host writes in its `configuration.bnix` still wins.

---

## Worked examples

### 1. Kitchen-sink: enable a tag, get everything by default

Modules:

```clojure
;; modules/git/default.bnix
:tags [dev terminal]

;; modules/ripgrep/default.bnix
:tags [dev terminal]

;; modules/firefox/default.bnix
:tags [browsers gui-only]
```

Host:

```clojure
;; hosts/whiterabbit/enabled-tags.bnix
{:enabled [dev terminal browsers]}
```

Resolved active set: `{git, ripgrep, firefox}`. No edits, no opt-ins, no
disables. The host gets the tag's full default-on roster.

### 2. Edited tag: enable a tag minus one module

Modules (same as above).

Host:

```clojure
{:enabled [dev
           [browsers -firefox]]}
```

Resolved: `{git, ripgrep}`. Firefox is on `browsers` by default, but the host
subtracted it under `browsers`. Note that if firefox also had `:tags [gui-only]`
and the host enabled `gui-only`, firefox would still be active via that tag.

### 3. Opt-in plus: pull in a module that isn't default-on

Modules:

```clojure
;; modules/qutebrowser-experimental/default.bnix
:tags-opt-in [browsers]                  ;; never on by default
```

Host:

```clojure
{:enabled [[browsers +qutebrowser-experimental]]}
```

Resolved active set includes `qutebrowser-experimental`. Without the `+`,
enabling `browsers` alone would not pull it in (because it lives in
`:tags-opt-in`, not `:tags`).

If the host wrote `+qutebrowser-experimental` under a tag the module does
**not** list in `:tags-opt-in` (e.g. `[terminal +qutebrowser-experimental]`),
the validator rejects the host config with a `tag/opt-in mismatch` error.

### 4. Hard disable: tag would pull a module in, but `:disabled` wins

Modules:

```clojure
;; modules/piper/default.bnix
:tags [dev]
```

Host:

```clojure
{:enabled  [dev]
 :disabled [piper]}
```

Resolved: piper is **off**. Even though `dev` would activate it by default,
the global `:disabled` list applies last and outranks every tag-based
contribution.

This is the right tool when you want a module gone everywhere it touches —
no matter how many tags would otherwise pull it in.

### 5. Tag-override interaction (browsers case)

```clojure
;; modules/firefox/default.bnix
:tags [browsers gui-only]
:tag-overrides {browsers {:myConfig.modules.firefox.default true}}
```

Host A:

```clojure
{:enabled [browsers]}
```

Resolved: `firefox` is on (via `browsers` defaults), and `firefox.default` is
set to `true` via the override. The host can still write
`:myConfig.modules.firefox.default false` in its `configuration.bnix` to win
over the `mkDefault`.

Host B:

```clojure
{:enabled [gui-only]}
```

Resolved: `firefox` is on (via `gui-only` defaults), but `firefox.default` is
**not** set by the override — the `:tag-overrides` map only fires for the
specific tag that listed it, and `gui-only` has no override entry.

Host C:

```clojure
{:enabled [[browsers +firefox]]}   ;; hypothetical: firefox in :tags-opt-in
```

If `firefox` lived in `:tags-opt-in [browsers]` rather than `:tags [browsers]`,
a `+firefox` plus would **not** trigger the override. Overrides apply to
default-on memberships only.

---

## Historical: bundle audit

The pre-migration bundle audit (Phase A) counted every `mkDefault` in the now-
deleted `bundles/*/default.bnix`:

| metric                              | count |
|-------------------------------------|------:|
| Total `mkDefault` hits              |   141 |
| Pure enable-wiring                  |   132 |
| Value-overrides (non-`enable`)      |     9 |

All 9 value-overrides clustered in two bundles (`browsers` x 8, `theming` x 1).
The other 20 bundles were pure enable-wiring and collapsed into tag membership
with zero overrides. The 9 surviving cases are the reason `:tag-overrides`
exists in the schema rather than being deferred.

The migration is complete: `bundles/` no longer exists, `firn bundle …` prints
a pointed error pointing at the equivalent `firn tag …` form, and the
underlying graph (`firn` with no args) has no `bundle` node.

---

## Editing host tags from the CLI

```bash
firn tag enable  <tag>            # add <tag> to :enabled (no flags)
firn tag disable <tag>            # remove <tag> from :enabled entirely
firn tag opt-in  <tag> <module>   # add +<module> under <tag>
firn tag opt-out <tag> <module>   # add -<module> under <tag>
firn tag status                   # show :enabled / :disabled + resolved active set

firn module enable  <module>      # remove <module> from :disabled (un-blacklist)
firn module disable <module>      # append <module> to :disabled (hard off)
```

`firn enable <name>` / `firn disable <name>` is the daily shortcut: targets a
tag by default; routes to `firn module enable/disable` when `<name>` matches a
known module. All edits mutate `hosts/<current-host>/enabled-tags.bnix` in
place via the tag-edit parser (AST-aware, idempotent round-trip).

---

## Validation

- `firn validate` checks each module's `:tags` and `:tags-opt-in` entries are
  bare symbols, that `:tag-overrides` paths exist in the schema, and that no
  module declares the same tag in both `:tags` and `:tags-opt-in`.
- `firn validate` checks each host's `:enabled` flags reference real modules,
  that every `+name` flag matches a module whose `:tags-opt-in` lists this
  tag, and that every name in `:disabled` is a real module.
- `firn tag resolve <host>` is the runtime debugger — it prints the per-tag
  contributions, the unions, the disabled subtraction, and the final active
  set.

The reference fixture lives at
[`docs/fixtures/tags-example.bnix`](fixtures/tags-example.bnix) and is the
canonical syntax that the parser must accept.
