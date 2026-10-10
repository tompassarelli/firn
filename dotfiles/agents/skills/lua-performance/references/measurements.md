# Lua performance: measurements

Contents:
- Method
- Results (per iteration)
- What each pair compares (emitted Lua)
- Rejected candidates
- Reproduce

Read when revising `lua-performance` or re-measuring a rule. Measured
2026-10-09 on smashcraft 8cc0a7316, TypeScriptToLua 1.37.1, Wisp's stock
LUA_32BITS Lua 5.3 (`~/.cache/wisp/lua32/<hash>/lua`, resolved by
smashcraft:ts/scripts/wisp/luaRuntimes.ts `stockLua`).

## Method

Same counter as smashcraft:ts/test/lua/entry.ts (the Lua32 test cost
counter): `debug.sethook` count hook and `collectgarbage("count")` with the GC
stopped. Differences: hook step 1 instead of 1000, so counts are exact, and
allocation is read once before and after instead of at hook ticks. Each case
runs once to warm scratch tables, then 1000 iterations counted; columns are
per iteration. The wall column is one unleased `os.clock` run of 100,000
iterations with the GC on: indicative only, used where the counter is blind
to C work. The `empty` row (4 instr) is loop overhead in every row.

The `warcraft-numbers` plugin was left out because its number rules reject
`%` and `!`; no case uses a float literal, so emitted Lua is the same.
Allocation under about 60 B in string rows is string-table noise:
`string.template` and `string.concat` emit identical Lua yet differ by 57 B.

## Results (per iteration; arrays of 8 numbers, 8 fighters, 8-entry Map/Set)

| case | instr | bytes | wall µs |
| --- | --- | --- | --- |
| empty | 4.0 | 0 | 0.028 |
| append.spread | 66.0 | 617 | 2.059 |
| append.slice-push | 73.0 | 312 | 1.606 |
| append.loop-copy | 84.0 | 312 | 1.504 |
| push.method | 97.0 | 0 | 0.797 |
| push.index | 97.0 | 0 | 0.857 |
| push.counter | 62.0 | 0 | 0.410 |
| iterate.forEach | 101.0 | 1 | 0.666 |
| iterate.for-of | 40.0 | 0 | 0.611 |
| iterate.index-length | 87.0 | 0 | 0.559 |
| iterate.index-cached | 71.0 | 0 | 0.436 |
| transform.map-filter | 212.0 | 369 | 4.670 |
| transform.loop-new | 52.0 | 184 | 1.566 |
| transform.loop-scratch | 57.0 | 1 | 0.781 |
| find.some-closure | 76.5 | 73 | 0.898 |
| find.loop | 25.5 | 0 | 0.394 |
| find.includes | 41.0 | 1 | 0.279 |
| object.spread | 56.0 | 361 | 3.847 |
| object.literal | 11.0 | 184 | 0.687 |
| object.mutate | 5.0 | 0 | 0.051 |
| vec.new | 11.0 | 120 | 0.370 |
| vec.scratch | 10.0 | 0 | 0.090 |
| lookup.map-get | 11.0 | 0 | 0.128 |
| lookup.record | 6.0 | 0 | 0.055 |
| member.set-has | 16.3 | 0 | 0.159 |
| member.record-flag | 9.0 | 0 | 0.075 |
| mapiter.for-of-entries | 297.0 | 2297 | 7.839 |
| mapiter.forEach | 321.0 | 1465 | 7.141 |
| mapiter.values | 263.0 | 1505 | 7.621 |
| mapiter.array | 48.0 | 0 | 0.712 |
| mapupdate.map-set | 26.3 | 0 | 0.286 |
| mapupdate.record | 8.0 | 0 | 0.068 |
| optional.chain | 11.5 | 0 | 0.086 |
| optional.explicit | 13.5 | 0 | 0.114 |
| destructure.array | 11.0 | 0 | 0.139 |
| destructure.index | 7.0 | 0 | 0.060 |
| destructure.object | 9.0 | 0 | 0.084 |
| destructure.object-dot | 9.0 | 0 | 0.084 |
| string.template | 15.0 | 177 | 1.778 |
| string.concat | 15.0 | 120 | 2.074 |
| string.build-concat | 66.0 | 370 | 5.991 |
| string.build-join | 83.0 | 84 | 3.018 |
| string.build-join-noclear | 65.0 | 84 | 3.098 |
| key.string | 15.0 | 5 | 0.640 |
| key.numeric | 8.0 | 2 | 0.047 |
| string.build-tableconcat | 75.0 | 0 | 2.162 |
| call.inherited-method | 11.0 | 0 | 0.128 |
| call.plain-function | 11.0 | 0 | 0.070 |
| construct.class | 18.0 | 88 | 0.561 |
| construct.literal | 6.0 | 88 | 0.237 |

## What each pair compares (emitted Lua)

- append: `[...a, x]` → `__TS__SparseArrayNew(table.unpack(a))` +
  `__TS__SparseArrayPush` + `{__TS__SparseArraySpread(...)}`; `slice-push` →
  `__TS__ArraySlice` + `a[#a+1]`; `loop-copy` → while loop with `#nums`.
- push: `.push(x)` and `a[a.length] = x` both emit `a[#a + 1] = x`;
  `.length = 0` emits `__TS__ArraySetLength`; `counter` writes `a[k+1]`.
- iterate: `forEach` → `__TS__ArrayForEach` with a callback; for-of →
  `for _, v in ipairs(a)`; index loops → `while j < #a`.
- find: `.some(closure)` captures a per-iteration local, so `OP_CLOSURE`
  allocates each call (73 B); `forEach`'s callback captures only module
  upvalues and is reused by Lua 5.3's closure cache (1 B).
- object: `{...o, hp}` → `__TS__ObjectAssign({}, o, {hp = i})`.
- lookup/member/mapupdate: `map:get`, `set:has`, `map:set` are lualib
  method calls; the Record forms are one table index.
- mapiter: for-of over `map`/`map.values()` → `__TS__Iterator`, which builds
  a result table and a `[k, v]` pair per step; `map:forEach` walks the
  linked key list.
- optional: `a?.b?.c ?? 0` → `local t = a and a.b; x = t and t.c or 0`.
- destructure: `const [a, b] = p` → `table.unpack(p, 1, 2)`; object
  destructuring → one temp plus field reads.
- string: templates and `+` both → `("p" .. tostring(i)) .. ":" ..`;
  `s += v + ","` → `s = s .. tostring(v) .. ","`; join → `table.concat`.
- key: `` `${a}:${b}` `` → two `tostring` and a concat (interned, so only
  new keys allocate); numeric → `a * 64 + b`.
- call/construct: `leaf:damage()` resolves through two `__index` metatables
  in C, so it counts the same as a plain call (11) but runs 0.128 µs against
  0.070; `__TS__New` → `setmetatable({}, proto)` plus the constructor chain.

## Rejected candidates (no counted win)

- Template strings against concatenation: identical Lua.
- Object destructuring against dot access: 9 against 9.
- Inherited method against plain function: 11 against 11 counted; the wall
  gap is C metatable work, so judge it with `bun wisp perf compare`.
- For-of against a cached-length index loop: 40 against 71 counted, but
  wall 0.66 against 0.52 µs; prefer the index loop in hot paths.

## Reproduce

Create a scratch worktree, `cd ts && bun install --frozen-lockfile`, put the
three files below at ts/probe/cases.ts, ts/probe/entry.ts and
ts/tsconfig.probe.json, then:

```sh
bun --bun node_modules/typescript-to-lua/dist/tstl.js -p tsconfig.probe.json
cd build/probe && "$LUA32" probe.lua   # name, instructions/1000 iters, KB, wall s/100k iters
```

### tsconfig.probe.json

```json
{
  "extends": "./tsconfig.lua-tests.json",
  "compilerOptions": { "outDir": "build/probe", "types": ["lua-types/5.3"] },
  "include": ["probe/*.ts"],
  "tstl": {
    "luaTarget": "5.3", "luaBundle": "probe.lua", "luaBundleEntry": "probe/entry.ts",
    "noImplicitSelf": true, "noHeader": true,
    "luaPlugins": []
  }
}
```

### probe/entry.ts

```ts
import { cases } from "./cases";
const N = 1000;
for (const [name, run] of cases) {
  run(1);
  collectgarbage("collect");
  collectgarbage("stop");
  let ticks = 0;
  const before = collectgarbage("count");
  debug.sethook(() => { ticks++; }, "", 1);
  run(N);
  debug.sethook();
  const after = collectgarbage("count");
  collectgarbage("restart");
  const t0 = os.clock();
  run(100 * N);
  print(`${name}\t${ticks}\t${after - before}\t${os.clock() - t0}`);
}
```

### probe/cases.ts

```ts
type Vec = { x: number; y: number };
type Fighter = { id: number; hp: number; pos: Vec; shield?: { hp: number } };

const nums: number[] = [1, 2, 3, 4, 5, 6, 7, 8];
const fighters: Fighter[] = [];
for (let i = 0; i < 8; i++) fighters.push({ id: i, hp: 100, pos: { x: i, y: 0 }, ...(i % 2 === 0 ? { shield: { hp: 50 } } : {}) });
let sink = 0;
let sinkArr: number[] = [];
let sinkObj: Fighter = fighters[0]!;
let sinkStr = "";
const scratch: number[] = [];
const skeyed: Record<string, number> = {};
const nkeyed: Record<number, number> = {};
const scratchVec: Vec = { x: 0, y: 0 };

const map = new Map<number, Fighter>();
const record: Record<number, Fighter> = {};
const set = new Set<number>();
const flags: Record<number, true> = {};
for (const f of fighters) { map.set(f.id, f); record[f.id] = f; set.add(f.id); flags[f.id] = true; }

class Base { constructor(public hp: number) {} damage(n: number): void { this.hp -= n; } }
class Mid extends Base {}
class Leaf extends Mid {}
const leaf = new Leaf(100);
const plain = { hp: 100 };
const damage = (target: { hp: number }, n: number): void => { target.hp -= n; };

const pair: [number, number] = [3, 4];

export const cases: [string, (n: number) => void][] = [
  ["empty", (n) => { for (let i = 0; i < n; i++) sink = i; }],

  ["append.spread", (n) => { for (let i = 0; i < n; i++) sinkArr = [...nums, i]; }],
  ["append.slice-push", (n) => { for (let i = 0; i < n; i++) { const a = nums.slice(); a.push(i); sinkArr = a; } }],
  ["append.loop-copy", (n) => { for (let i = 0; i < n; i++) { const a: number[] = []; for (let j = 0; j < nums.length; j++) a[j] = nums[j]!; a[a.length] = i; sinkArr = a; } }],

  ["push.method", (n) => { for (let i = 0; i < n; i++) { scratch.length = 0; for (let j = 0; j < 8; j++) scratch.push(j); } }],
  ["push.index", (n) => { for (let i = 0; i < n; i++) { scratch.length = 0; for (let j = 0; j < 8; j++) scratch[scratch.length] = j; } }],
  ["push.counter", (n) => { for (let i = 0; i < n; i++) { let k = 0; for (let j = 0; j < 8; j++) scratch[k++] = j; } }],

  ["iterate.forEach", (n) => { for (let i = 0; i < n; i++) nums.forEach((v) => { sink += v; }); }],
  ["iterate.for-of", (n) => { for (let i = 0; i < n; i++) for (const v of nums) sink += v; }],
  ["iterate.index-length", (n) => { for (let i = 0; i < n; i++) for (let j = 0; j < nums.length; j++) sink += nums[j]!; }],
  ["iterate.index-cached", (n) => { for (let i = 0; i < n; i++) { const len = nums.length; for (let j = 0; j < len; j++) sink += nums[j]!; } }],

  ["transform.map-filter", (n) => { for (let i = 0; i < n; i++) sinkArr = nums.map((v) => v * 2).filter((v) => v > 4); }],
  ["transform.loop-new", (n) => { for (let i = 0; i < n; i++) { const out: number[] = []; for (const v of nums) { const d = v * 2; if (d > 4) out.push(d); } sinkArr = out; } }],
  ["transform.loop-scratch", (n) => { for (let i = 0; i < n; i++) { let k = 0; for (const v of nums) { const d = v * 2; if (d > 4) scratch[k++] = d; } } }],

  ["find.some-closure", (n) => { for (let i = 0; i < n; i++) { const id = i % 8; sink = fighters.some((f) => f.id === id) ? 1 : 0; } }],
  ["find.loop", (n) => { for (let i = 0; i < n; i++) { const id = i % 8; let hit = 0; for (const f of fighters) if (f.id === id) { hit = 1; break; } sink = hit; } }],
  ["find.includes", (n) => { for (let i = 0; i < n; i++) sink = nums.includes(6) ? 1 : 0; }],

  ["object.spread", (n) => { for (let i = 0; i < n; i++) sinkObj = { ...fighters[0]!, hp: i }; }],
  ["object.literal", (n) => { for (let i = 0; i < n; i++) { const f = fighters[0]!; sinkObj = { id: f.id, hp: i, pos: f.pos }; } }],
  ["object.mutate", (n) => { for (let i = 0; i < n; i++) fighters[0]!.hp = i; }],

  ["vec.new", (n) => { for (let i = 0; i < n; i++) { const v: Vec = { x: i, y: i + 1 }; sink = v.x + v.y; } }],
  ["vec.scratch", (n) => { for (let i = 0; i < n; i++) { scratchVec.x = i; scratchVec.y = i + 1; sink = scratchVec.x + scratchVec.y; } }],

  ["lookup.map-get", (n) => { for (let i = 0; i < n; i++) sinkObj = map.get(i % 8)!; }],
  ["lookup.record", (n) => { for (let i = 0; i < n; i++) sinkObj = record[i % 8]!; }],
  ["member.set-has", (n) => { for (let i = 0; i < n; i++) sink = set.has(i % 8) ? 1 : 0; }],
  ["member.record-flag", (n) => { for (let i = 0; i < n; i++) sink = flags[i % 8] === true ? 1 : 0; }],
  ["mapiter.for-of-entries", (n) => { for (let i = 0; i < n; i++) for (const [, f] of map) sink += f.hp; }],
  ["mapiter.forEach", (n) => { for (let i = 0; i < n; i++) map.forEach((f) => { sink += f.hp; }); }],
  ["mapiter.values", (n) => { for (let i = 0; i < n; i++) for (const f of map.values()) sink += f.hp; }],
  ["mapiter.array", (n) => { for (let i = 0; i < n; i++) for (const f of fighters) sink += f.hp; }],
  ["mapupdate.map-set", (n) => { for (let i = 0; i < n; i++) map.set(i % 8, fighters[i % 8]!); }],
  ["mapupdate.record", (n) => { for (let i = 0; i < n; i++) record[i % 8] = fighters[i % 8]!; }],

  ["optional.chain", (n) => { for (let i = 0; i < n; i++) sink = fighters[i % 8]?.shield?.hp ?? 0; }],
  ["optional.explicit", (n) => { for (let i = 0; i < n; i++) { const f = fighters[i % 8]; const s = f === undefined ? undefined : f.shield; sink = s === undefined ? 0 : s.hp; } }],

  ["destructure.array", (n) => { for (let i = 0; i < n; i++) { const [a, b] = pair; sink = a + b; } }],
  ["destructure.index", (n) => { for (let i = 0; i < n; i++) { const a = pair[0]; const b = pair[1]; sink = a + b; } }],
  ["destructure.object", (n) => { for (let i = 0; i < n; i++) { const { x, y } = fighters[0]!.pos; sink = x + y; } }],
  ["destructure.object-dot", (n) => { for (let i = 0; i < n; i++) { const p = fighters[0]!.pos; sink = p.x + p.y; } }],

  ["string.template", (n) => { for (let i = 0; i < n; i++) sinkStr = `p${i}:${i + 1}`; }],
  ["string.concat", (n) => { for (let i = 0; i < n; i++) sinkStr = "p" + i + ":" + (i + 1); }],
  ["string.build-concat", (n) => { for (let i = 0; i < n; i++) { let s = ""; for (const v of nums) s += (v + i) + ","; sinkStr = s; } }],
  ["string.build-join", (n) => { for (let i = 0; i < n; i++) { let k = 0; for (const v of nums) scratch[k++] = v + i; scratch.length = k; sinkStr = scratch.join(","); } }],
  ["string.build-join-noclear", (n) => { for (let i = 0; i < n; i++) { let k = 0; for (const v of nums) scratch[k++] = v + i; sinkStr = table.concat(scratch as unknown as string[], ",", 1, k); } }],
  ["key.string", (n) => { for (let i = 0; i < n; i++) { const a = i & 7; const b = i & 56; skeyed[`${a}:${b}`] = i; } }],
  ["key.numeric", (n) => { for (let i = 0; i < n; i++) { const a = i & 7; const b = i & 56; nkeyed[a * 64 + b] = i; } }],
  ["string.build-tableconcat", (n) => { for (let i = 0; i < n; i++) { let k = 0; for (const v of nums) scratch[k++] = v; scratch.length = k; sinkStr = table.concat(scratch as unknown as string[], ","); } }],

  ["call.inherited-method", (n) => { for (let i = 0; i < n; i++) leaf.damage(0); }],
  ["call.plain-function", (n) => { for (let i = 0; i < n; i++) damage(plain, 0); }],
  ["construct.class", (n) => { for (let i = 0; i < n; i++) sinkObj.pos = new Leaf(i) as unknown as Vec; }],
  ["construct.literal", (n) => { for (let i = 0; i < n; i++) sinkObj.pos = { hp: i } as unknown as Vec; }],
];
```
