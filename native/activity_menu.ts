// SPDX-License-Identifier: MIT OR Apache-2.0

import { spawnSync } from "node:child_process";

const maxCommandOutput = 16777216;

type CaptureResult =
  | { kind: "ok"; status: number; stdout: string; stderr: string }
  | { kind: "error"; errno: number };

function capture(argv: string[], input: string): CaptureResult {
  const result = spawnSync(argv[0], argv.slice(1), {
    encoding: "utf8", env: process.env, input, maxBuffer: maxCommandOutput,
  });
  return result.error
    ? { kind: "error", errno: Math.abs(Number((result.error as NodeJS.ErrnoException).errno ?? 5)) }
    : { kind: "ok", status: result.status ?? 1, stdout: result.stdout ?? "", stderr: result.stderr ?? "" };
}

function menuChoice(prompt: string, items: string): string | null {
  const result = capture(["rofi", "-dmenu", "-p", prompt], items);
  if (result.kind === "error") {
    process.stderr.write(`activity-menu: cannot start rofi: errno ${result.errno}\n`);
    return null;
  }
  if (result.status !== 0) return null;
  const choice = result.stdout.trim();
  return choice === "" ? null : choice;
}

export function run(args: string[]): number {
  const mode = args.length === 0 ? "goto" : args[0];
  const verb = mode === "--move" ? "move-to-activity" : mode === "--assign" ? "assign" : "goto";
  const prompt = mode === "--move" ? "move to activity" : mode === "--assign" ? "assign to activity" : "activity";
  const result = capture(["activity", "list", "--menu"], "");
  if (result.kind === "error") {
    process.stderr.write(`activity-menu: cannot start activity: errno ${result.errno}\n`);
    return 1;
  }
  if (result.status !== 0) return result.status;
  const choice = menuChoice(prompt, result.stdout);
  if (choice === null) return 0;
  const child = spawnSync("activity", [verb, choice], { env: process.env, stdio: "inherit" });
  return child.error ? 126 : (child.status ?? 1);
}

if (import.meta.main) process.exitCode = run(Bun.argv.slice(2));
