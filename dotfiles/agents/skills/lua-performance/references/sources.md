# Lua performance: sources

Read when revising `lua-performance` or when a rule needs its evidence.
Researched 2026-10-09. Each entry: tag, title, link, author, date, what we
took. Every rule in `SKILL.md` was then measured; see measurements.md.

## PUC Lua (official)

- [gems-tips] "Lua Performance Tips", Lua Programming Gems ch. 2, Roberto
  Ierusalimschy, 2008. https://www.lua.org/gems/sample.pdf. Took: locals are
  registers, upvalues slower, globals slowest; cache hot globals in locals.
  Table growth rehashes (array part to a power of two); constructors presize,
  `{[1]=x}` lands in the hash part; tables shrink only on rehash. Strings are
  interned: creation costs, comparison is cheap; `s = s .. x` in a loop is
  quadratic, use a buffer plus `table.concat`. Reuse tables and closures.
- [impl50] "The Implementation of Lua 5.0", J.UCS 11(7), Ierusalimschy, de
  Figueiredo, Celes, 2005. https://www.lua.org/doc/jucs05.pdf. Took: array
  part sized to the largest n with over half of 1..n used, about half the
  memory of hash storage; register VM; upvalues shared and closed on scope
  exit.
- [man53] Lua 5.3 Reference Manual, lua.org.
  https://www.lua.org/manual/5.3/manual.html. Took: `#t` is any border for a
  non-sequence; `next`/`pairs` order is unspecified even for numeric keys;
  `__gc` only counts if present at `setmetatable`; LUA_32BITS means 32-bit
  integers that wrap and binary32 floats.
- [lgc] Lua 5.3.6 `lstate.c`/`lgc.c`, https://github.com/lua/lua/tree/v5.3.6.
  Took: `LUAI_GCPAUSE 200` (cycle starts when memory doubles), `LUAI_GCMUL 200`;
  5.3 is incremental only, no generational mode.
- [ltable] Lua 5.3.6 `ltable.c`, same tree. Took: `computesizes` picks the
  power-of-two array size more than half full; `luaH_getn` binary-searches,
  so `#t` (TSTL `.length`) is O(log n): cache it outside loops.
- [lstring] Lua 5.3.6 `llimits.h`/`lstring.c`, same tree. Took:
  `LUAI_MAXSHORTLEN 40`; strings up to 40 bytes are interned and hashed on
  creation, so each built key string pays hashing and a table lookup.
- [lvm] Lua 5.3.6 `lopcodes.h`/`lvm.c`, same tree. Took: globals are
  `OP_GETTABUP` on `_ENV`; `OP_NEWTABLE` carries constructor presize;
  `OP_SETLIST` flushes 50 items; one `OP_CONCAT` joins a whole `a..b..c` run;
  `OP_CLOSURE` allocates unless 5.3's `getcached` finds a closure with
  identical upvalues (measured: forEach callback 1 B, capturing `some` 73 B).
- [ws18-gc] "Garbage Collection in Lua", Lua Workshop 2018 slides,
  Ierusalimschy. https://www.lua.org/wshop18/Ierusalimschy.pdf. Took: pause
  and step multiplier semantics; incremental GC trades shorter pauses for
  more total work; 5.4 generational mode helps only when most objects die
  young, so it is irrelevant on Warcraft's 5.3.

## LuaJIT (to know what does not apply)

- [luajit-num] "Numerical Computing Performance Guide", Mike Pall, LuaJIT
  wiki 2012 (archived:
  https://web.archive.org/web/2017/http://wiki.luajit.org/Numerical-Computing-Performance-Guide).
  Took: under LuaJIT, manual CSE and hoisting can hurt and the compiler does
  it better. PUC 5.3 has no JIT, so manual caching into locals, hoisting and
  avoiding allocation all still pay.

## TypeScriptToLua (official)

- [tstl-caveats] TSTL docs, "Caveats",
  https://typescripttolua.github.io/docs/caveats. Took: `.length` is `#`
  (holes change it); `sort` is unstable `table.sort`; `for...in` order
  differs from JS; 200-local limit.
- [tstl-config] TSTL docs, "Configuration",
  https://typescripttolua.github.io/docs/configuration. Took: `luaTarget`,
  `luaLibImport` modes, `noImplicitSelf` drops the extra self argument.
- [tstl-lualib] TSTL `src/lualib/*.ts`,
  https://github.com/TypeScriptToLua/TypeScriptToLua/tree/master/src/lualib
  (v1.37.1). Took: `ArrayForEach`/`Map`/`Filter` call the callback once per
  element; `Map`/`Set` keep `items` plus next/previous key tables (three
  writes per insert); their iterators allocate a result table and a `[k, v]`
  pair per step; `__TS__New` is `setmetatable({}, proto)` plus constructor.
- [tstl-visitors] TSTL `src/transformation/visitors/` (spread,
  loops/for-of, optional-chaining, template),
  https://github.com/TypeScriptToLua/TypeScriptToLua/tree/master/src/transformation/visitors.
  Took: for-of over an array emits `ipairs`, over Map/Set `__TS__Iterator`;
  `$range` gives a numeric for; optional chains become temp locals with
  `and`; templates become `..` with `tostring`. Our 1.37.1 output for
  `[...a, x]` uses `__TS__SparseArrayNew/Push/Spread` (seen in emitted Lua).

## Warcraft III Reforged (community reverse-engineering; no Blizzard statement found)

- [hive-gc] "1.32 The LUA GC is seemingly disabled", Hive Workshop,
  ScrewTheTrees, Dr Super Good and others, 2021-02-20.
  https://www.hiveworkshop.com/threads/1-32-the-lua-gc-is-seemingly-disabled.330735.
  Took: 1.31 ran the stock GC and desynced; 1.32+ collects on its own
  schedule (6 to 300 s observed), user control removed, and allocating tables
  every 0.01 s prevented collection. Allocation rate is the rule that matters.
- [hive-sync] "SyncedTable", Eikonium, 2021, updated 2024-08,
  https://www.hiveworkshop.com/threads/syncedtable.353715/ and "Causes of
  desync", Ricola3D and others, 2019-2025,
  https://www.hiveworkshop.com/threads/causes-of-desync.317486/. Took:
  `pairs` order differs between clients, so state changes inside it desync;
  handle ids are not synced; GC can recycle handle wrappers at different
  times per client; Warcraft runs Lua 5.3.
- [blz-131] Blizzard, "1.31.0 Patch Notes",
  https://us.forums.blizzard.com/en/warcraft3/t/1-31-0-patch-notes/5721
  (searched, not read). Took: Lua arrived in 1.31; no performance detail.
