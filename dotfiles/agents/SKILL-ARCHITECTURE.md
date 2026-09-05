# Skills and hooks architecture

Snapshot: 2026-09-05. This is an operator map, not an always-loaded instruction
file. The live catalog remains authoritative: `agents status --json`,
`agents inspect <id>`, and `agents path <id>`.

## At a glance

| Source owner | Distilled guides | Full-note entrypoints | Total |
| --- | ---: | ---: | ---: |
| North | 28 | 25 | 53 |
| NixOS configuration / Firn | 17 | 10 | 27 |
| Beagle | 4 | 4 | 8 |
| **Total** | **49** | **39** | **88** |

There are 49 families, not 88 independent workflows. Of the 49 distilled guides,
41 are active and 8 are off. All 39 full-note entrypoints are off in normal
discovery but remain available from source through `agents path`. The 56
topic-note files are supporting resources, not additional skills.

The same catalog also contains 3 modules and 11 hooks: 102 units total.
Bootstrap instructions and provider support files are separate from that count.
Provider-bundled system skills and historical session catalogs are not part of
these 88 entries.

## Source to use

```text
SOURCE REPOSITORIES
├── north-v2:agent-machinery/        reusable workflows and run-design package
├── nixos-config:dotfiles/agents/    operator policy, catalog, hook sources
├── nixos-config:modules/north-profile/firn/skills/
└── beagle:integrations/north/ + beagle:store/integrations/north/
                     │
                     ▼
CATALOG COMPOSITION
├── north-v2:agent-machinery/catalog.json        package registrations
└── nixos-config:dotfiles/agents/catalog-config.json
    └── owner registrations + module/support links + distribution targets
                     │
                     ▼
NORTH ACTIVATION — agents sync
  published source + permissions → resolved activity + generation
                     │
          ┌──────────┼──────────────────┐
          ▼          ▼                  ▼
  INSTRUCTIONS     SKILLS              HOOKS / ADAPTERS
  baseline and     discovery metadata  event-driven code
  active modules   → selected guide    + activity gate
                   → requested notes
          │          │                  │
          └──────────┼──────────────────┘
                     ▼
  shared / Codex / Claude / North / project-scoped consumers
  (only the targets declared for each distribution)
```

Permission is not activity: an enabled module may claim permitted members, and
a supported active unit may activate its hook. Hook execution does not depend
on the model reading the related skill. A distribution target is not proof of
provider event wiring or execution.

The normal context path stays small: skill name/description → one complete
distilled guide → only the notes needed for the current question. This matches
[Codex's progressive-disclosure model](https://developers.openai.com/codex/skills).

## Complete skill tree

`{distilled,reference}` expands to two exact registered IDs. A lone
`-distilled` is one entry. `○` marks an inactive distilled guide; all reference
entrypoints are inactive. Subject groups below aid navigation; they are not
new directories or activation modules.

```text
88 skill entries / 49 families
├── north-v2:agent-machinery/skills/ — 53 entries
│   ├── Run design
│   │   ├── agent-run-design-{distilled,reference}
│   │   └── work-ownership-distilled
│   ├── Engineering and authoring
│   │   ├── babashka-development-distilled
│   │   ├── build-vs-reuse-{distilled,reference} ○
│   │   ├── competitive-development-loop-distilled
│   │   ├── external-code-{distilled,reference}
│   │   ├── greenfield-{distilled,reference} ○
│   │   ├── importing-skills-{distilled,reference}
│   │   ├── planning-{distilled,reference}
│   │   ├── prior-art-{distilled,reference}
│   │   ├── production-hardening-{distilled,reference}
│   │   ├── program-craftsmanship-{distilled,reference}
│   │   ├── program-stewardship-{distilled,reference}
│   │   ├── rust-development-{distilled,reference}
│   │   ├── skill-maintenance-{distilled,reference}
│   │   ├── terse-{distilled,reference} ○
│   │   ├── verification-{distilled,reference}
│   │   └── webdev-{distilled,reference} ○
│   └── Three.js
│       ├── threejs-animation-{distilled,reference}
│       ├── threejs-fundamentals-{distilled,reference}
│       ├── threejs-geometry-{distilled,reference}
│       ├── threejs-interaction-{distilled,reference}
│       ├── threejs-lighting-{distilled,reference}
│       ├── threejs-loaders-{distilled,reference}
│       ├── threejs-materials-{distilled,reference}
│       ├── threejs-postprocessing-{distilled,reference}
│       ├── threejs-shaders-{distilled,reference}
│       └── threejs-textures-{distilled,reference}
├── nixos-config — 27 entries
│   ├── nixos-config:dotfiles/agents/skills/ — 25
│   │   ├── agent-policy-{distilled,reference}
│   │   ├── agent-runtime-incident-distilled
│   │   ├── beagle-system-design-{distilled,reference}
│   │   ├── clause-authoring-distilled
│   │   ├── cloudflare-deploy-{distilled,reference}
│   │   ├── convo-{distilled,reference}
│   │   ├── digitalocean-access-distilled
│   │   ├── estimate-{distilled,reference}
│   │   ├── greywrought-development-distilled ○
│   │   ├── guard-authoring-{distilled,reference}
│   │   ├── machine-capacity-distilled
│   │   ├── nix-development-distilled
│   │   ├── project-structure-{distilled,reference}
│   │   ├── repo-safety-{distilled,reference}
│   │   ├── resource-safe-search-distilled
│   │   └── todo-{distilled,reference}
│   └── nixos-config:modules/north-profile/firn/skills/ — 2
│       └── firn-{distilled,reference}
└── beagle — 8 entries
    ├── beagle:integrations/north/skills/ — 2
    │   └── beagle-authoring-{distilled,reference}
    └── beagle:store/integrations/north/skills/ — 6
        ├── code-as-facts-{distilled,reference} ○
        ├── fact-modeling-{distilled,reference} ○
        └── store-modeling-{distilled,reference} ○
```

## Guide and full-note layout

Each tree leaf resolves to a skill directory containing its entrypoint,
for example `north-v2:agent-machinery/skills/verification-distilled/SKILL.md`.

```text
north-v2:agent-machinery/skills/
├── verification-distilled/
│   └── SKILL.md                     complete ordinary workflow
└── verification-reference/
    ├── SKILL.md                     detailed framing and topic index
    └── references/
        ├── evidence-selection.md
        ├── failure-diagnosis.md
        └── pricing-and-progress.md
```

Small full notes remain in their reference entrypoint. Larger ones split by
topic. Distilled-only skills can also have conditional resources: there is no
requirement to manufacture a second entrypoint. Existing scripts, fixtures,
and UI metadata stay with their consuming skill.

The detailed layer preserves constraints, rationale, examples, alternatives,
and labeled exploration for future re-distillation. It is not a second set of
routinely loaded instructions.

## Actual activation modules

```text
agent-machinery
├── delegation
│   ├── agent-run-design-distilled
│   └── work-ownership-distilled
└── agent-practice
    ├── babashka-development-distilled
    ├── build-vs-reuse-distilled ○
    ├── competitive-development-loop-distilled
    ├── external-code-distilled
    ├── greenfield-distilled ○
    ├── planning-distilled
    ├── prior-art-distilled
    ├── production-hardening-distilled
    ├── program-craftsmanship-distilled
    ├── program-stewardship-distilled
    ├── rust-development-distilled
    ├── skill-maintenance-distilled
    ├── terse-distilled ○
    └── verification-distilled
```

The other skills use direct catalog roots. Module membership never overrides
an explicit off permission.

## Hooks: separate from skills

| Stable hook ID | Role / event | Supports | Active |
| --- | --- | --- | --- |
| `beagle-session-start` | Beagle context / SessionStart | `beagle-authoring-distilled` | yes |
| `code-upstream-guard` | Graph-owned source protection / PreToolUse | `code-as-facts-distilled` | no |
| `comment-bloat-guard` | Comment advice only; never denies / PreToolUse | direct root | no |
| `concrete-model-identity-guard` | Concrete model record protection / PreToolUse | `todo-distilled` | yes |
| `corpus-scan-guard` | Conversation archive search protection / PreToolUse | `convo-distilled` | yes |
| `firn-system-policy` | System policy adapter / PreToolUse | `firn-distilled` | yes |
| `git-blind-stage-guard` | Explicit Git staging / PreToolUse | `repo-safety-distilled` | yes |
| `launch-critical-worktree-guard` | Main checkout and live pin protection / PreToolUse | `repo-safety-distilled` | yes |
| `resource-safe-search-guard` | Bounded filesystem search / PreToolUse | `resource-safe-search-distilled` | yes |
| `session-kill-guard` | Session and child-process protection / PreToolUse | `repo-safety-distilled`, `agent-machinery` | yes |
| `tripwire-guard` | Destructive command and upload protection / PreToolUse | `repo-safety-distilled` | yes |

The event column describes the implementation's protocol, not a claim that
every declared provider target invokes it. Codex source wiring in
`nixos-config:modules/codex/requirements.toml` invokes the 9 active hooks:
one SessionStart context hook and eight PreToolUse policy hooks.
The inactive comment advisor and project-scoped graph guard are not in that
managed Codex event list.

Source owners:

- Nine hooks: `nixos-config:dotfiles/agents/hooks/`. Firn's adapter calls the
  implementation owned at `nixos-config:native/system_policy_native.bjs`.
- Session context: `beagle:integrations/north/hooks/beagle-session-start.sh`.
- Graph-owned source protection:
  `beagle:store/integrations/north/hooks/code-upstream-guard.sh`.
- Shared activation support: `nixos-config:dotfiles/agents/lib/`.

Keep hook IDs stable across source, activity checks, provider wiring, and
fixtures. Improve human-readable titles and descriptions without changing IDs
merely for symmetry. In particular, label the comment hook as advisory and the
tripwire by the operations it protects. Enforcement behavior, permissions,
and provider event wiring are outside this naming cleanup.

