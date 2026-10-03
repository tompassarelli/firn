---
name: wurst-development-distilled
description: >-
  Develop Warcraft III maps and tooling in WurstScript, including Wurst
  projects, compiler workflows, tests, compile-time object data, and WC3 UI.
  Use when the requested source or project toolchain is Wurst; it does not
  require migrating existing Lua or Jass projects.
---

# Wurst development

Use the project's Wurst source and toolchain to build the requested map change.
Wurst is a typed language that can compile to either Warcraft III Jass or Lua;
it is not a request to rewrite a project that already owns its source in Lua or
Jass.

## Start from the project

Read the project instructions, `wurst.build`, and its dependency or lock files.
Keep the declared Warcraft patch, script target, compiler, and standard-library
versions aligned. Use the project's pinned compiler and its nearest supported
typecheck, test, and map-build commands. VS Code diagnostics are useful while
editing, but a scoped project command is the check for the actual build. If the
Wurst extension offers to install or update a compiler and the project pin is
not clear, inspect the selected version before accepting a different toolchain.

Before reaching for a Warcraft native or writing a helper, check the standard
library version resolved by the project and nearby consumer code. The Wurst
standard library already supplies typed native wrappers, vector tuples,
geometry helpers, frame APIs, object editing, and reusable game systems. The
[Wurst manual](https://wurstlang.org/manual.html) and
[standard-library reference](https://wurstlang.org/stdlib) explain the public
language and APIs; the project's resolved sources decide what it can use.

## Build feedback into the code

For simulation rules that do not need live engine handles, keep the calculation
in pure Wurst functions and cover the exact rule with `Wurstunit` tests. This
works well for movement, collision, damage, stocks, and input-state transitions.
Run a focused test or typecheck while iterating, then build and launch the map
for claims that depend on Warcraft timing, native handles, rendering, or
multiplayer synchronization. Headless tests do not prove those engine behaviors.

Use value tuples such as the standard library's `vec2` for coordinates and
small physics values; tuple assignment copies the value and does not need
destruction. Use classes when state needs identity or a managed lifecycle.
Extension functions and the cascade operator can keep WC3 handle operations
readable. Give lambdas an expected callback type: closures capture locals by
value, while a Wurst `code` callback cannot capture them. Follow the resolved
library's ownership and destruction rules for classes and stored listeners.

Use `@compiletime` object editing when authored unit, ability, item, or upgrade
data belongs in code. Prefer the library's typed object-definition APIs and ID
generators so generated rawcodes stay stable and collision-free. Let the
project's build inject or package those results; keep generated object files
out of the source of truth. Use compile-time asset or import facilities when
they remove repeated manual map setup, not as a requirement for every map.

## Separate game objects from UI

Warcraft's `widget` handle is a game-world object abstraction (such as a unit,
item, or destructable). Custom UI uses `framehandle`; inspect the resolved
`Framehandle` and `ClosureFrames` APIs rather than treating a UI frame as a
widget.

Create or acquire UI frames after game time has started, and create/cache each
frame handle outside `GetLocalPlayer()` scope. Frame events are synchronized
and fire on all clients; visual frame state may be changed locally. Keep local
presentation changes separate from gameplay state. For buttons or edit boxes
that retain keyboard focus, use the library's
`framehandle.onClickReleaseFocus()` where appropriate so game hotkeys work
again after a click. Frame positioning uses Warcraft UI coordinates; check the
library documentation for 4:3 versus full-screen frame behavior.

## Choose the target that the map uses

Honor the map's configured Jass or Lua target. Wurst source can target both,
but Warcraft and their runtime APIs still have differences; validate behavior
on the actual target when it matters. The Wurst compiler supports
`wurst.build` data injection in Lua mode, so use the project build path instead
of maintaining a separate handwritten Lua script.

Jass Hot Code Reload (JHCR) is an optional, alpha workflow for maps whose
compiled script is Jass. It rewrites a Jass map script and emits preload data
that must be inserted into the running map; it does not hot reload Lua maps or
replace the ordinary compile/build path. Use it only when the project targets
Jass and that extra setup is useful.

## Current UI and tooling practices

For UI work, object-data workflow changes, Grill verification or a new workspace,
read [modern Wurst workflow guidance](references/modern-workflow.md). Prefer
existing UI components and headless layout checks before raw frame plumbing;
confirm newer APIs against the resolved project versions and verify engine
interaction natively. Keep a project AGENTS.md with its actual pinned commands.
