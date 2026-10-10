---
name: lua-performance
description: >-
  Cut frame cost and Lua instruction or allocation counts in TypeScriptToLua
  code on PUC Lua 5.3 (Warcraft III, Wisp): over-ceiling Lua32 test costs,
  `bun wisp perf compare` failures, per-frame allocation and GC pressure.
grounded: 2026-10-09
written: 2026-10-09
metadata:
  kind: domain
---

# Lua performance

Measure before and after; never guess. Numbers below are per operation from
TSTL 1.37.1 on Smashcraft's LUA_32BITS 5.3 with the Lua32 test counter
(count hook, GC stopped), on 8-element arrays and 8-entry maps. Cases, emitted
Lua and the harness: [measurements](references/measurements.md). Sources:
[sources](references/sources.md).

## Measure
- Use the repo's own counters: Lua32 test costs (smashcraft:ts/test/lua/cost-baseline.tsv)
  for instructions and allocation, `bun wisp perf <scenario> --samples` and
  `bun wisp perf compare` for frame cost including natives.
- Read the emitted Lua (`build/`) for the hot function before changing it.
- The instruction counter sees only Lua VM opcodes. `ipairs`, `tostring`,
  `table.concat`, string interning and metatable `__index` chains run in C
  and count as one instruction or none; confirm those with perf compare.
- Allocation is the cost that matters most in Warcraft: its GC is not
  user-tunable and may not finish a cycle under steady allocation [hive-gc].

## Rules for per-frame and per-tick code
1. Never iterate a `Map` or `Set`. Keep an array beside it. For-of over an
   8-entry Map: 297 instr, 2297 B; `forEach` 321 instr, 1465 B; the array:
   48 instr, 0 B.
2. Replace `map`/`filter`/`some` chains with one loop. `map().filter()`:
   212 instr, 369 B; loop into a new array 52 instr, 184 B; into a reused
   scratch array 57 instr, 0 B.
3. Never spread to copy-and-change. `{ ...o, hp }` 56 instr, 361 B; a full
   literal 11 instr, 184 B; mutation 5 instr, 0 B. `[...a, x]` 66 instr,
   617 B; `a.slice()` then push 73 instr, 312 B; push in place 0 B.
4. Hoist capturing closures out of the frame. `fighters.some(f => f.id === id)`
   76 instr, 73 B (a new closure per call); a plain loop 26 instr, 0 B. Lua
   5.3 reuses a closure only when its upvalues are identical.
5. Reuse scratch tables and vectors. A fresh `{ x, y }` costs 120 B per call;
   writing a module-level scratch costs 0 B at the same instruction count.
6. Track a fill count instead of `arr.length = 0` plus `push`. Clear and
   refill of 8: 97 instr; an index counter 62 instr. Pass the count to
   `table.concat(t, sep, 1, k)` instead of trimming the array.
7. Cache `.length` before the loop: TSTL emits `#t` (O(log n)) on every
   check. 87 to 71 instr per 8 elements. For-of counts 40 but its `ipairs`
   C call hides real cost (0.66 µs against 0.52 µs wall).
8. Use a plain `Record` keyed by number for hot lookups, not `Map`/`Set`.
   `get` 11 to 6 instr, `set` 26 to 8, `has` 16 to 9. Never iterate the
   Record with `for...in`/`pairs` in simulation: order differs per client.
9. Key tables by numbers, not built strings. `` t[`${a}:${b}`] `` 15 instr
   and 0.64 µs; `t[a * 64 + b]` 8 instr and 0.05 µs.
10. Index tuples instead of array destructuring: `const [a, b] = pair` emits
    `table.unpack`, 11 instr; `pair[0]`, `pair[1]` 7. Object destructuring is
    free (9 against 9).
11. Prefer object literals to `new Class` for small hot records: 18 to 6
    instr at the same 88 B.
12. Build strings in a reused table plus `table.concat`, not `s +=`: 370 B to
    84 B per 8-piece string.
13. Keep `?.` and `??`: TSTL emits `and`/`or`, 11.5 instr against 13.5 for
    hand-written undefined checks.

## Ignore
- LuaJIT advice (trust the compiler, avoid manual hoisting): PUC 5.3 has no
  JIT, so manual caching into locals still pays [luajit-num].
- Template strings against `+` concatenation: identical emitted Lua.
