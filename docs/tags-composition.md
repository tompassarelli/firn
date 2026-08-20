# Tags (composition model)

Tags are the **only** way modules get composed. Each module declares which tags it belongs to; each host enables a list of tags; the resolver unions the memberships and subtracts a per-host disabled list. This replaced the legacy `myConfig.bundles.*` pattern (per-bundle sub-options + `mkDefault` proxies), which has been fully removed — there is no `bundles/` directory.

Schema (locked during the bundle→tags audit — 132 enable-wiring hits collapsed into tag membership; 9 value-override hits, all in `browsers` and `theming`, are preserved via `:tag-overrides`):

### Module-side: `modules/<name>/default.bnix`

```clojure
(nix/module [config lib pkgs ...]
  {:options.myConfig.modules.<name>.enable
    (lib.mkEnableOption "...")

   ;; --- tag membership (the only required new clause) ---
   :tags [browsers gui-only]                  ;; default-on memberships
   :tags-opt-in [headless-ok]                 ;; opt-in only — host must use +<name>
   :tag-overrides                             ;; OPTIONAL: per-tag value overrides
     {browsers {:myConfig.modules.<name>.default true}}

   :config
     (lib.mkIf config.myConfig.modules.<name>.enable
       { ... })})
```

- `:tags` — list of bare symbols. Membership is default-on: enabling the tag enables the module unless the host edits the tag with `-<name>` or hard-disables it.
- `:tags-opt-in` — same shape, but the module is **not** enabled by the tag automatically. The host must opt in explicitly with `+<name>` in the tag's edit-flag list. Omit the clause when empty.
- `:tag-overrides` — optional map of `tag => {option-path value, ...}`. When the resolver activates the module *because of* that tag, the listed value-overrides are applied as `mkDefault`. This replaces the small set of non-`enable` proxies the audit flagged (8 in `browsers` for `<browser>.default`, 1 in `theming` for `stylix.chosenTheme`). Omit when not needed.

Tags live in the `.bnix` source only — `firn repo build` strips them out, so the generated `.nix` is unchanged.

### Host-side: `hosts/<host>/enabled-tags.bnix`

```clojure
{:enabled
  [terminal                                       ;; bare tag = defaults, no edits
   [browsers -gjoa +qutebrowser-experimental]     ;; vector = tag + edit-flags
   [theming -nerd-fonts]]
 :disabled [piper auto-upgrade]}                  ;; hard-off, wins over everything
```

- `:enabled` entries are either a bare symbol (the tag, no edits) or a 1+N vector `[tag flag…]` where each `flag` is a symbol prefixed `-` or `+`:
  - `-<module>` removes that module from this tag's default-on set (per-tag scope — other tags that include the module still count).
  - `+<module>` adds the module, but only if the module's `:tags-opt-in` includes this tag.
- `:disabled` is a global hard-off list applied **after** the union. A module here is off no matter how many tags would otherwise pull it in.

### Resolution algorithm

```
active := union over each enabled-tag T of (
  defaults := { m | T appears in m.:tags }
  minuses  := { x | -x in T's edit-flags }
  pluses   := { x | +x in T's edit-flags AND T appears in x.:tags-opt-in }
  (defaults \ minuses) ∪ pluses
)
enabled-modules := active \ host.:disabled
```

For each module in `enabled-modules`, the resolver also walks each tag T it joined via *defaults* (not via `+`) and applies any `:tag-overrides[T]` entries as `mkDefault`. This lets `browsers` set `firefox.default = true` for the module that joined via the `browsers` tag.

### Tooling

```bash
firn tag list                       # tag universe + module counts
firn tag show steam                 # tags + opt-in tags + overrides for one module
firn tag filter gpu-required        # all modules with that tag
firn tag resolve <host>             # show the active module set + which tag pulled each in
firn tag index                      # write .beagle-cache/tags.jsonl
firn tag index stdout               # jsonl to stdout (pipe into jq/fzf)
```

`firn tag resolve` is the debugger — given a host, it prints each enabled tag, the defaults it contributes, the minus/plus edits, the global disabled mask, and the final union. Use this when "why is module X enabled?" is non-obvious.

**Full reference**: [`docs/TAGS.md`](docs/TAGS.md) — worked examples (kitchen-sink, edited tag, opt-in plus, hard disable) and the fixture used by the validator.
