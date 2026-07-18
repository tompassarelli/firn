#!/usr/bin/env node
// Adapted from https://github.com/Green-PT/honey-for-devs hooks/ (MIT)
// PostToolUse hook: collapse repetitive Bash output before it lands in context,
// and stash the original so any detail stays retrievable.
//
// Always-on (no mode gate). Two emit conditions:
//   • ≥1 lines were collapsed (repeated-run dedup)
//   • ANSI stripping alone saved >200 chars (pure token noise)
// Falls through silently on small / already-clean output. Fail-open everywhere:
// any throw → exit 0 → original result reaches the model unchanged.
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");
const crypto = require("crypto");
const { spawnSync } = require("child_process");

function emit(obj) { process.stdout.write(JSON.stringify(obj)); }
function passthrough() { process.exit(0); } // no output → original result is kept

// Stay well inside the provider's 10s hook deadline. The child owns parsing,
// compression, and cache I/O; the supervisor emits only a complete, validated
// JSON envelope. A slow filesystem or pathological payload is therefore a
// clean no-op, never a provider timeout or a partial replacement envelope.
if (process.env.LOGCOMPRESS_INNER !== "1") {
  try {
    const inputRead = spawnSync(
      "timeout",
      ["--signal=TERM", "--kill-after=0.1s", "1s", "cat"],
      {
        stdio: [0, "pipe", "ignore"],
        maxBuffer: 64 * 1024 * 1024,
        timeout: 2000,
        killSignal: "SIGKILL",
      },
    );
    if (inputRead.status !== 0) process.exit(0);
    const input = inputRead.stdout;
    const maxBuffer = Math.min(
      Math.max(input.length * 2 + 1024 * 1024, 1024 * 1024),
      64 * 1024 * 1024,
    );
    const child = spawnSync(
      "timeout",
      ["--signal=TERM", "--kill-after=0.2s", "2s", process.execPath, __filename],
      {
        input,
        env: { ...process.env, LOGCOMPRESS_INNER: "1" },
        encoding: "utf8",
        maxBuffer,
        timeout: 3000,
        killSignal: "SIGKILL",
      },
    );
    if (child.status === 0 && child.stdout) {
      const payload = JSON.parse(child.stdout);
      if (payload?.hookSpecificOutput?.hookEventName === "PostToolUse") {
        process.stdout.write(child.stdout);
      }
    }
  } catch {
    // No output preserves the provider's original tool result.
  }
  process.exit(0);
}

try {
  if (process.env.LOGCOMPRESS_TEST_HANG === "1") {
    if (process.env.LOGCOMPRESS_TEST_PID_FILE) {
      fs.writeFileSync(process.env.LOGCOMPRESS_TEST_PID_FILE, String(process.pid));
    }
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 30000);
  }
  const { compress } = require(path.join(__dirname, "logcompress.js"));
  const input = JSON.parse(fs.readFileSync(0, "utf8"));
  if ((input.tool_name || input.toolName) !== "Bash") passthrough();

  const resp = input.tool_response ?? input.toolResponse ?? input.tool_result;
  // Claude's Bash PostToolUse result is an object. updatedToolOutput must retain
  // that object shape; returning only the replacement string is rejected by the
  // hook runtime and causes a generic hook error.
  if (!resp || typeof resp !== "object" || Array.isArray(resp)) passthrough();
  const textField = ["stdout", "output", "content"]
    .find((field) => typeof resp[field] === "string");
  if (!textField) passthrough();
  const text = resp[textField];
  if (typeof text !== "string" || !text) passthrough();

  const { view, saved, dropped } = compress(text);
  // emit when lines collapsed OR ANSI stripping alone saved significant chars
  if (dropped < 1 && saved <= 200) passthrough();

  // stash original so per-line detail is recoverable
  const cacheDir = process.env.XDG_CACHE_HOME
    ? path.join(process.env.XDG_CACHE_HOME, "claude-logcompress")
    : path.join(os.homedir(), ".cache", "claude-logcompress");
  const hash = crypto.createHash("sha256").update(text).digest("hex").slice(0, 16);
  const cachePath = path.join(cacheDir, `${hash}.json`);
  const cacheTmp = `${cachePath}.${process.pid}.tmp`;
  fs.mkdirSync(cacheDir, { recursive: true, mode: 0o700 });
  try {
    fs.writeFileSync(cacheTmp, text, { mode: 0o600 });
    fs.renameSync(cacheTmp, cachePath);
  } finally {
    fs.rmSync(cacheTmp, { force: true });
  }

  const parts = [];
  if (dropped > 0) {
    parts.push(`collapsed ${dropped} repeated line(s)`);
    if (saved > 0) parts.push(`saved ${saved} chars total`);
  } else if (saved > 0) {
    parts.push(`stripped ${saved} ANSI chars`);
  }
  const note = `\n[logcompress: ${parts.join(", ")}. Full output: cat ${cacheDir}/${hash}.json]`;
  emit({
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      updatedToolOutput: { ...resp, [textField]: view + note },
    },
  });
} catch {
  passthrough(); // fail open — never corrupt a tool result
}
