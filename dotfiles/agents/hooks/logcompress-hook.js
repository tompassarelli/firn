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
const { compress } = require(path.join(__dirname, "logcompress.js"));

function emit(obj) { process.stdout.write(JSON.stringify(obj)); }
function passthrough() { process.exit(0); } // no output → original result is kept

try {
  const input = JSON.parse(fs.readFileSync(0, "utf8"));
  if ((input.tool_name || input.toolName) !== "Bash") passthrough();

  const resp = input.tool_response ?? input.toolResponse ?? input.tool_result;
  const text = typeof resp === "string" ? resp
    : resp && typeof resp === "object" ? (resp.stdout ?? resp.output ?? resp.content ?? "") : "";
  if (typeof text !== "string" || !text) passthrough();

  const { view, saved, dropped } = compress(text);
  // emit when lines collapsed OR ANSI stripping alone saved significant chars
  if (dropped < 1 && saved <= 200) passthrough();

  // stash original so per-line detail is recoverable
  const cacheDir = process.env.XDG_CACHE_HOME
    ? path.join(process.env.XDG_CACHE_HOME, "claude-logcompress")
    : path.join(os.homedir(), ".cache", "claude-logcompress");
  const hash = crypto.createHash("sha256").update(text).digest("hex").slice(0, 16);
  fs.mkdirSync(cacheDir, { recursive: true });
  fs.writeFileSync(path.join(cacheDir, `${hash}.json`), text);

  const parts = [];
  if (dropped > 0) parts.push(`collapsed ${dropped} repeated line(s)`);
  if (saved > 0) parts.push(`stripped ${saved} ANSI chars`);
  const note = `\n[logcompress: ${parts.join(", ")}. Full output: cat ${cacheDir}/${hash}.json]`;
  emit({ hookSpecificOutput: { hookEventName: "PostToolUse", updatedToolOutput: view + note } });
} catch {
  passthrough(); // fail open — never corrupt a tool result
}
