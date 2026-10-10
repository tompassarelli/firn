---
name: wurst-development
description: >-
  Develop Warcraft III maps and tooling in WurstScript (projects, compiler
  workflows, tests, compile-time object data, WC3 UI) when the requested source
  or toolchain is Wurst; existing Lua or Jass projects need no migration.
grounded: 2026-10-09
written: 2026-10-09
metadata:
  kind: domain
---

# Wurst development

- Use the project's Wurst source and toolchain without replacing existing Lua or Jass source.
- Read project instructions, `wurst.build` and dependency locks before editing.
- Align the declared Warcraft patch, Jass/Lua target, compiler and standard-library versions.
- Use the pinned compiler's focused typecheck, test and map-build commands.
- Inspect the selected compiler version before accepting an editor-offered installation or update when the pin is unclear.
- Check resolved standard-library sources and nearby consumers before writing helpers or using natives.
- Consult the [manual](https://wurstlang.org/manual.html) and [standard library](https://wurstlang.org/stdlib) for public APIs while treating resolved project sources as available capability.
- Keep simulation calculations independent of live handles in pure functions covered by exact-rule `Wurstunit` tests.
- Build and launch the map for timing, handle, rendering and multiplayer claims after focused feedback.
- Use value tuples such as `vec2` for coordinates and small physics values with copying assignment and no destruction.
- Use classes for identity or managed lifecycles under the resolved library's ownership and destruction rules.
- Use extension functions and cascades to clarify handle operations.
- Give lambdas an expected callback type and account for by-value local captures and noncapturing `code` callbacks.
- Author unit, ability, item and upgrade data through `@compiletime` typed object APIs and stable, collision-free ID generators when code owns that data.
- Let the project build inject/package generated object data without making generated files a second source.
- Use compile-time import facilities when they remove repeated manual setup.
- Use `framehandle` for custom UI and `widget` for game-world units, items and destructables.
- Inspect resolved `Framehandle` and `ClosureFrames` APIs before UI work.
- Create/acquire UI frames after game time starts and cache shared handles outside `GetLocalPlayer()`.
- Treat frame events as synchronized across clients and separate local visual state from gameplay mutations.
- Release retained button/edit-box focus with `framehandle.onClickReleaseFocus()` where appropriate.
- Check Warcraft UI-coordinate behavior for 4:3 and full-screen frame positioning.
- Validate target-specific runtime behavior on the configured Jass or Lua backend.
- Use the project build's `wurst.build` injection in Lua mode instead of handwritten parallel Lua.
- Use optional alpha JHCR only for Jass maps when its rewritten map script and inserted preload data justify the setup.
- Read [modern-workflow.md](references/modern-workflow.md) for UI components, headless layout checks, object-data changes, Grill checks or workspace creation.
- Confirm newer APIs against resolved versions and verify engine interaction natively.
- Record actual pinned commands in the project's AGENTS.md.
