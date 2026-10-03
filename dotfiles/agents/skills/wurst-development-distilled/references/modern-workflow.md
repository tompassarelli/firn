# Modern Wurst workflow guidance

Distilled from the owner-supplied June 12 and July 16, 2026 Wurst articles and
AI/CI notes. These describe upstream capabilities, not proof that a consuming
project's pinned compiler, Grill or library exposes every API.

## Reuse UI before writing frame plumbing

For new or substantially changed custom UI, evaluate Wurst Table Layout before
manual anchor calculations or another bespoke click overlay. Its components
cover panels, rows, text, forms, selection controls, dialogs and bars. The
library's `interactive`/`selectable` helpers address whole-row/card input and
visual children; buttons normally release keyboard focus. Inspect its
AGENTS.md, AI_USAGE.md and WC3_FRAMEHANDLE_GUIDE.md before using it.

Prefer consistent spacing and sized text cells. `placeSafe` targets ordinary
HUD-safe panels; `placeVisuallySafe` is for deliberate sidecars. Named cached
HUD helpers are preferable to copied child-index assumptions. Confirm the
resolved revision and compatibility before adding a dependency; do not rewrite
working interfaces solely because a toolkit exists.

Use `checkFits()`/`inspect()` in focused headless tests to catch unsized cells
and declared-size overflow. These do not measure real font shaping, click
routing, focus release, draw order, widescreen presentation or multiplayer
safety. Verify those in the native map after layout checks pass. Create shared
frame handles consistently and keep local presentation out of gameplay state.

Inspected toolkit revision: 0dcd360302e0dad3f2a1580eacfca371d06d2c46.
Source: https://github.com/Frotty/wurst-table-layout/tree/0dcd360302e0dad3f2a1580eacfca371d06d2c46
The toolkit was not installed by this documentation change.

## Faster focused verification

Current Grill offers `grill typecheck` and `grill test NAME`; use them where
supported by the project pin. Otherwise use the existing pinned project's
focused equivalents. Do not update the compiler or replace a working runner
just to match an article. Keep AGENTS.md specific: source locations, patch,
backend, version locks, actual commands and native verification boundaries.

For new projects, current `grill generate` can align patch, Lua/Jass target,
Core Jass and standard-library branch, and optionally provide AGENTS.md and CI
scaffolding. For established projects, preserve authoritative locks and update
these together when needed. CI/Docker is useful only when it serves the actual
project verification path; it does not prove native game behavior. Report
macOS toolchain support separately from Warcraft/client gameplay support.

## Object data and newer language features

Use typed high-level object-generation wrappers before raw field setters.
The modern VS Code object editor can synchronize binary object data and WTS,
follow references and preview rich tooltips. Select one authority: authored
compile-time definitions or editor-owned object data. Do not hand-edit generated
object data as a parallel source. Export tools may help a deliberate migration.

Check whether the pinned compiler supports `?.` before using it. The reported
initial semantics evaluate the receiver once and skip arguments for null;
assignment targets and array-member access are excluded. Do not infer those
semantics from compilation alone when the target/backend matters. Similarly,
verify the resolved standard library's multibyte-string and asset behavior
instead of assuming the latest upstream defaults or silently replacing pins.
