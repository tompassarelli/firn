import { test, expect } from "bun:test";
import { decide, type Situation } from "./main-red";

test("GitHub workflow-run confirmation protocol (REST actions/workflow-jobs, kind 4)", () => {
  const job = { id: 7, name: "test", conclusion: "failure", steps: [{ name: "Test", number: 2, conclusion: "failure" }] };
  const recorded: Situation = { attempt: 1, conclusion: "failure", original: [job], confirmed: [], previous: { sha: "parent", conclusion: "success" }, commits: [{ sha: "culprit", parents: ["parent"], message: "land", files: ["src/main.rs"] }], onMain: true, head: "culprit" };
  expect(decide(recorded).kind).toBe("confirm");
  const confirmation = { ...recorded, attempt: 2, confirmed: [job] };
  expect(decide(confirmation)).toMatchObject({ kind: "revert", shas: ["culprit"] });
  expect(decide({ ...confirmation, previous: { sha: "unrelated", conclusion: "success" } }).kind).toBe("report");
  expect(decide({ ...confirmation, previous: { sha: "parent", conclusion: "failure" } }).kind).toBe("report");
  expect(decide({ ...confirmation, attempt: 3 }).kind).toBe("report");
  expect(decide({ ...confirmation, conclusion: "success", confirmed: [{ ...job, conclusion: "success", steps: [] }] }).kind).toBe("report");
  expect(decide({ ...confirmation, confirmed: [{ ...job, steps: [{ name: "Other", number: 2, conclusion: "failure" }] }] }).kind).toBe("report");
  expect(decide({ ...confirmation, commits: [{ ...recorded.commits[0]!, files: [".github/workflows/tests.yml"] }] }).kind).toBe("report");
  expect(decide({ ...confirmation, commits: [{ ...recorded.commits[0]!, message: "Revert bad landing\n\nSheriff-Reverts: prior" }] }).kind).toBe("report");
  expect(decide({ ...confirmation, onMain: false }).kind).toBe("report");
  expect(decide({ ...confirmation, head: "tip", onMain: true, commits: [{ sha: "tip", parents: ["culprit"], message: "second", files: ["src/lib.rs"] }, ...recorded.commits] })).toMatchObject({ kind: "revert", shas: ["tip", "culprit"] });
});
