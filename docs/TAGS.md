# Tags

Module composition is stored as JSON beside the Nix sources. A module's
`modules/<name>/metadata.json` declares `tags`, `optIn`, `overrides`,
`supports` and `flakeInputs`. A host's `hosts/<host>/tags.json` declares
`platform`, `enables`, `adds`, `drops`, `disables`, `turnsOn` and `turnsOff`.
`config/platforms.json` states whether a platform allows every module.

A module in an enabled tag is enabled by default, unless the host drops it
from that tag. Drops affect only that tag's contribution. Modules in `optIn`
join a tag only when the host adds them. Host disables and direct `turnsOff`
choices subtract from every tag; direct `turnsOn` choices enable a module
independently. An unsupported module or conflicting direct on/off choice is
rejected. Per-tag overrides apply to default members, rather than opt-ins.

```bash
firn tag enable <tag>
firn tag disable <tag>
firn tag opt-in <tag>+<module>
firn tag opt-out <tag>+<module>
firn tag status <host>
firn tag resolve <host>
firn module enable <module>
firn module disable <module>
firn repo build
firn check
```

For example, enabling `browsers` selects its default members. Dropping
`firefox` affects that contribution; another enabled tag may still select
it. Adding `chrome` is accepted only if its metadata permits opting into
`browsers`. Disabling a module removes it from all tag contributions.

Edit `.nix` for package/service configuration and the adjacent JSON for
composition. The shared `config/tags.nix` resolves host metadata during Nix
evaluation; no generated Nix output needs committing.
