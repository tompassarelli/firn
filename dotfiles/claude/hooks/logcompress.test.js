// Adapted from https://github.com/Green-PT/honey-for-devs hooks/ (MIT)
// Tests for LogCompressor + PostToolUse hook.
// Run with: node --test hooks/logcompress.test.js
"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { execFileSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { compress, expand } = require(path.join(__dirname, "logcompress.js"));
const HOOK = path.join(__dirname, "logcompress-hook.js");

// helper: run hook with payload + env, return stdout string (empty = passthrough)
const run = (payload, env = {}) =>
  execFileSync("node", [HOOK], {
    input: JSON.stringify(payload),
    env: { ...process.env, ...env },
    encoding: "utf8",
  });

// --- pure compressor ---------------------------------------------------------

const storm =
  "[12:00:00] INFO start\n" +
  Array.from({ length: 26 }, (_, i) => `[12:00:${String(i + 1).padStart(2, "0")}] WARN db refused, retrying`).join("\n") +
  "\n[12:00:27] ERROR gave up: host=db-primary\n[12:00:28] INFO ok\n";

test("collapses timestamped run", () => {
  const { dropped } = compress(storm);
  assert.equal(dropped, 25); // 26 WARN → 1 + (×26)
});

test("view is smaller than original", () => {
  const { view } = compress(storm);
  assert.ok(view.length < storm.length);
});

test("count recoverable via expand", () => {
  const { view } = compress(storm);
  const count = (expand(view).match(/\bWARN\b/g) || []).length;
  assert.equal(count, 26);
});

test("keeps non-collapsed lines", () => {
  const { view } = compress(storm);
  assert.ok(view.includes("ERROR gave up: host=db-primary"));
});

test("strips ANSI", () => {
  const { view } = compress("\x1b[31m" + storm);
  assert.ok(!view.includes("\x1b["));
});

test("small output not collapsed (below gate)", () => {
  const small = "\x1b[32mline\x1b[0m\na\na\na\n";
  assert.equal(compress(small).dropped, 0);
});

test("small output ANSI stripped even below gate", () => {
  const small = "\x1b[32mline\x1b[0m\na\na\na\n";
  assert.ok(!compress(small).view.includes("\x1b["));
});

test("distinct lines (stack trace) untouched", () => {
  const trace = Array.from({ length: 30 }, (_, i) => `  File "app/x${i}.py", line ${i}, in f${i}`).join("\n");
  assert.equal(compress(trace).dropped, 0);
});

// --- hook end-to-end ---------------------------------------------------------

// shared temp cache dir for hook tests
const cacheDir = fs.mkdtempSync(path.join(os.tmpdir(), "logcompress-cache-"));
const env = { XDG_CACHE_HOME: cacheDir };
// actual cache subdir the hook will create
const lcDir = path.join(cacheDir, "claude-logcompress");

const bashStorm = { tool_name: "Bash", tool_response: storm };

test("hook emits updatedToolOutput on storm", () => {
  const out = run(bashStorm, env);
  assert.ok(out.includes("updatedToolOutput"));
  assert.ok(out.includes("×26"));
});

test("hook stashes original to cache file", () => {
  const out = run(bashStorm, env);
  const hash = JSON.parse(out).hookSpecificOutput.updatedToolOutput.match(/cat .+\/(\w+)\.json/)[1];
  const stashed = fs.readFileSync(path.join(lcDir, `${hash}.json`), "utf8");
  assert.equal(stashed, storm);
});

test("hook retrieval note uses cat, not eso retrieve", () => {
  const out = run(bashStorm, env);
  const note = JSON.parse(out).hookSpecificOutput.updatedToolOutput;
  assert.ok(note.includes("cat "));
  assert.ok(!note.includes("eso retrieve"));
});

test("non-Bash tool passes through", () => {
  assert.equal(run({ tool_name: "Read", tool_response: storm }, env), "");
});

test("non-repetitive Bash passes through (no collapse, no ANSI)", () => {
  const trace = Array.from({ length: 30 }, (_, i) => `  File "app/x${i}.py", line ${i}, in f${i}`).join("\n");
  assert.equal(run({ tool_name: "Bash", tool_response: trace }, env), "");
});

test("malformed input fails open (no throw, no output)", () => {
  const out = execFileSync("node", [HOOK], { input: "not json", encoding: "utf8" });
  assert.equal(out, "");
});

// ANSI-savings gate: >200 ANSI chars stripped → emit even without collapse
test("ANSI-only savings >200 chars triggers emit", () => {
  // 10 lines, each with a long ANSI prefix — below 25-line collapse gate, but lots of ANSI
  const ansiHeavy = Array.from({ length: 10 }, (_, i) =>
    `\x1b[38;2;255;128;0m\x1b[1m\x1b[4m\x1b[48;2;0;0;128m[bold-color-underline-bg] line ${i}\x1b[0m`
  ).join("\n");
  // verify savings: ansi codes add up to > 200 chars
  const { saved, dropped } = compress(ansiHeavy);
  assert.ok(saved > 200, `expected saved > 200 chars, got ${saved}`);
  assert.equal(dropped, 0); // no collapse (below gate)

  const out = run({ tool_name: "Bash", tool_response: ansiHeavy }, env);
  assert.ok(out.includes("updatedToolOutput"), "hook should emit on ANSI-only savings > 200");
});

// ANSI-savings gate: ≤200 chars saved, no collapse → passthrough
test("ANSI-only savings ≤200 chars passes through", () => {
  // single line with minimal ANSI
  const ansiLight = "\x1b[32mok\x1b[0m";
  const { saved, dropped } = compress(ansiLight);
  assert.ok(saved <= 200);
  assert.equal(dropped, 0);
  assert.equal(run({ tool_name: "Bash", tool_response: ansiLight }, env), "");
});
