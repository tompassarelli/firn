// Adapted from https://github.com/Green-PT/honey-for-devs hooks/ (MIT)
// Tests for LogCompressor + PostToolUse hook.
// Run with: node --test hooks/logcompress.test.js
"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { execFileSync, spawn } = require("child_process");
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

const bashResult = (stdout) => ({
  stdout,
  stderr: "",
  interrupted: false,
  isImage: false,
  noOutputExpected: false,
});
const bashStorm = { tool_name: "Bash", tool_response: bashResult(storm) };

test("hook emits a shape-preserving updatedToolOutput object on storm", () => {
  const out = run(bashStorm, env);
  const updated = JSON.parse(out).hookSpecificOutput.updatedToolOutput;
  assert.equal(typeof updated, "object");
  assert.ok(updated.stdout.includes("×26"));
  assert.match(updated.stdout, /collapsed 25 repeated line\(s\)/);
  assert.match(updated.stdout, /saved \d+ chars total/);
  assert.doesNotMatch(updated.stdout, /ANSI/);
  assert.equal(updated.stderr, "");
  assert.equal(updated.interrupted, false);
  assert.equal(updated.isImage, false);
  assert.equal(updated.noOutputExpected, false);
});

test("hook stashes original to cache file", () => {
  const out = run(bashStorm, env);
  const stdout = JSON.parse(out).hookSpecificOutput.updatedToolOutput.stdout;
  const hash = stdout.match(/cat .+\/(\w+)\.json/)[1];
  const stashed = fs.readFileSync(path.join(lcDir, `${hash}.json`), "utf8");
  assert.equal(stashed, storm);
});

test("hook retrieval note uses cat, not eso retrieve", () => {
  const out = run(bashStorm, env);
  const note = JSON.parse(out).hookSpecificOutput.updatedToolOutput.stdout;
  assert.ok(note.includes("cat "));
  assert.ok(!note.includes("eso retrieve"));
});

test("non-Bash tool passes through", () => {
  assert.equal(run({ tool_name: "Read", tool_response: storm }, env), "");
});

test("non-repetitive Bash passes through (no collapse, no ANSI)", () => {
  const trace = Array.from({ length: 30 }, (_, i) => `  File "app/x${i}.py", line ${i}, in f${i}`).join("\n");
  assert.equal(run({ tool_name: "Bash", tool_response: bashResult(trace) }, env), "");
});

test("legacy string response fails open rather than emitting an invalid replacement shape", () => {
  assert.equal(run({ tool_name: "Bash", tool_response: storm }, env), "");
});

test("malformed input fails open (no throw, no output)", () => {
  const out = execFileSync("node", [HOOK], { input: "not json", encoding: "utf8" });
  assert.equal(out, "");
});

test("held-open stdin is cut off before the provider deadline", async () => {
  const started = Date.now();
  const child = spawn("node", [HOOK], {
    env: process.env,
    stdio: ["pipe", "pipe", "pipe"],
  });
  let stdout = "";
  let stderr = "";
  child.stdout.setEncoding("utf8").on("data", (chunk) => { stdout += chunk; });
  child.stderr.setEncoding("utf8").on("data", (chunk) => { stderr += chunk; });
  const status = await new Promise((resolve, reject) => {
    child.once("error", reject);
    child.once("close", resolve);
  });
  const elapsed = Date.now() - started;
  assert.equal(status, 0);
  assert.equal(stdout, "");
  assert.equal(stderr, "");
  assert.ok(elapsed >= 800, `stdin deadline fired implausibly early (${elapsed}ms)`);
  assert.ok(elapsed < 3000, `stdin pipe exceeded fail-open ceiling (${elapsed}ms)`);
});

test("missing compressor module fails open inside the supervisor", () => {
  const isolated = fs.mkdtempSync(path.join(os.tmpdir(), "logcompress-missing-module-"));
  const isolatedHook = path.join(isolated, "logcompress-hook.js");
  fs.copyFileSync(HOOK, isolatedHook);
  const out = execFileSync("node", [isolatedHook], {
    input: JSON.stringify(bashStorm),
    encoding: "utf8",
  });
  assert.equal(out, "");
  fs.rmSync(isolated, { recursive: true, force: true });
});

test("inner deadline turns a hung compressor into a clean no-op", () => {
  const pidFile = path.join(cacheDir, "hung-inner.pid");
  const started = Date.now();
  const out = run(bashStorm, {
    ...env,
    LOGCOMPRESS_TEST_HANG: "1",
    LOGCOMPRESS_TEST_PID_FILE: pidFile,
  });
  const elapsed = Date.now() - started;
  assert.equal(out, "");
  assert.ok(elapsed >= 1700, `deadline fired implausibly early (${elapsed}ms)`);
  assert.ok(elapsed < 4000, `deadline exceeded fail-open ceiling (${elapsed}ms)`);
  const innerPid = Number(fs.readFileSync(pidFile, "utf8"));
  assert.throws(
    () => process.kill(innerPid, 0),
    (error) => error?.code === "ESRCH",
    `inner process ${innerPid} survived its deadline`,
  );
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

  const out = run({ tool_name: "Bash", tool_response: bashResult(ansiHeavy) }, env);
  assert.ok(out.includes("updatedToolOutput"), "hook should emit on ANSI-only savings > 200");
  const stdout = JSON.parse(out).hookSpecificOutput.updatedToolOutput.stdout;
  assert.match(stdout, /stripped \d+ ANSI chars/);
  assert.doesNotMatch(stdout, /chars total/);
});

// ANSI-savings gate: ≤200 chars saved, no collapse → passthrough
test("ANSI-only savings ≤200 chars passes through", () => {
  // single line with minimal ANSI
  const ansiLight = "\x1b[32mok\x1b[0m";
  const { saved, dropped } = compress(ansiLight);
  assert.ok(saved <= 200);
  assert.equal(dropped, 0);
  assert.equal(run({ tool_name: "Bash", tool_response: bashResult(ansiLight) }, env), "");
});
