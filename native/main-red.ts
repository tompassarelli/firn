import { appendFileSync } from "node:fs";

export interface Step { name: string; conclusion: string | null; number: number }
export interface Job { id: number; name: string; conclusion: string | null; steps: Step[] }
export interface Commit { sha: string; parents: string[]; message: string; files: string[] }
export interface Situation {
  attempt: number;
  conclusion: string | null;
  original: Job[];
  confirmed: Job[];
  previous?: { sha: string; conclusion: string | null };
  commits: Commit[];
  onMain: boolean;
  head: string;
}
export type Decision = { kind: "none" | "report" | "confirm" | "revert"; reason: string; step?: string; job?: number; shas?: string[] };

export function decide(s: Situation): Decision {
  const job = [...s.original].sort((a, b) => a.id - b.id).find(j => j.conclusion === "failure" && j.steps.some(t => t.conclusion === "failure"));
  const step = job?.steps.find(t => t.conclusion === "failure");
  if (!job || !step) return { kind: s.conclusion === "success" ? "none" : "report", reason: "No failing test step was recorded" };
  const name = `${job.name}: ${step.name}`;
  const report = (reason: string): Decision => ({ kind: "report", reason, step: name });
  if (!s.onMain) return report("The failing commit is no longer on main; report only");
  if (s.attempt === 1) return { kind: "confirm", reason: "Confirm this failed job once; retain the original failure", step: name, job: job.id };
  if (s.attempt !== 2) return report("Confirmation budget exhausted; never rerun again");
  const confirmed = s.confirmed.find(j => j.name === job.name);
  if (s.conclusion !== "failure" || confirmed?.conclusion !== "failure" || !confirmed.steps.some(t => t.name === step.name && t.conclusion === "failure")) return report("The original step did not fail again; no confirmed culprit");
  if (/^(Set up job|Complete job|Post |Install |Checkout |Cache |Activate |Read setup |Toolchain |Run actions\/|Run oven-sh\/)/.test(step.name)) return report("A setup step failed; report infrastructure failure");
  if (s.previous?.conclusion !== "success") return report("The previous main run of this workflow was not green");
  if (!s.commits.length) return report("No landed commits after the previous run");
  let parent = s.previous.sha;
  for (const commit of [...s.commits].reverse()) {
    if (commit.parents.length !== 1 || commit.parents[0] !== parent) return report("The green run is not the landing's parent");
    if (/^Revert\b|^Sheriff-Reverts:/m.test(commit.message)) return report("Never revert a revert");
    if (commit.files.some(p => p.startsWith(".github/workflows/"))) return report("Never revert workflow changes");
    parent = commit.sha;
  }
  if (parent !== s.head) return report("The landed range does not end at the failing commit");
  return { kind: "revert", reason: "Same step failed twice after a green parent", step: name, shas: s.commits.map(c => c.sha) };
}

function run(command: string, args: string[]): string {
  const result = Bun.spawnSync([command, ...args], { stdout: "pipe", stderr: "pipe", env: process.env });
  if (result.exitCode !== 0) throw new Error(`${command} ${args[0]} exited ${result.exitCode}: ${result.stderr.toString().trim()}`);
  return result.stdout.toString();
}
const git = (...args: string[]) => run("git", args).trim();
const gh = (...args: string[]) => run("gh", args);
function api<T>(path: string): T { return JSON.parse(gh("api", path)) as T; }
interface Run { id: number; workflow_id: number; head_sha: string; head_branch: string; event: string; run_attempt: number; conclusion: string | null; html_url: string }
interface Issue { number: number; title: string; body: string }
const repo = () => {
  const value = process.env.GH_REPO;
  if (!value || !/^[\w.-]+\/[\w.-]+$/.test(value)) throw new Error("GH_REPO must name owner/repository");
  return `repos/${value}`;
};
function jobs(id: number, attempt: number): Job[] {
  const pages = JSON.parse(gh("api", "--paginate", "--slurp", `${repo()}/actions/runs/${id}/attempts/${attempt}/jobs?per_page=100`)) as { jobs: Job[] }[];
  return pages.flatMap(p => p.jobs);
}
function issue(): Issue | undefined {
  const issues = JSON.parse(gh("issue", "list", "--state", "open", "--search", '"main is red" in:title', "--json", "number,title,body", "--limit", "100")) as Issue[];
  return issues.find(i => i.title === "main is red");
}
function report(existing: Issue | undefined, marker: string, body: string): void {
  const content = `${existing?.body ?? "Main CI failures and confirmed culprit decisions."}\n\n${marker}\n${body}`;
  const args = existing ? ["issue", "edit", String(existing.number)] : ["issue", "create", "--title", "main is red"];
  gh(...args, "--body", content);
  if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, `${body}\n`);
  console.log(body);
}

export function sheriff(id: number): void {
  const ci = api<Run>(`${repo()}/actions/runs/${id}`);
  if (ci.head_branch !== "main" || ci.event !== "push") return;
  const original = jobs(id, 1);
  if (ci.conclusion === "success" && ci.run_attempt === 1) return;
  const existing = issue();
  const marker = `<!-- main-red:${id}:${ci.run_attempt} -->`;
  if (existing?.body.includes(marker)) return;
  git("fetch", "-q", "origin", "main");
  const onMain = Bun.spawnSync(["git", "merge-base", "--is-ancestor", ci.head_sha, "origin/main"]).exitCode === 0;
  const history = api<{ workflow_runs: Run[] }>(`${repo()}/actions/workflows/${ci.workflow_id}/runs?branch=main&event=push&status=completed&per_page=100`).workflow_runs;
  const prior = history.filter(r => r.id < id).sort((a, b) => b.id - a.id)[0];
  let commits: Commit[] = [];
  if (prior) {
    const ancestor = Bun.spawnSync(["git", "merge-base", "--is-ancestor", prior.head_sha, ci.head_sha]);
    if (ancestor.exitCode === 0) {
      commits = git("log", "--first-parent", "-z", "--format=%H%n%P%n%B", `${prior.head_sha}..${ci.head_sha}`).split("\0").filter(x => x.trim()).map(entry => {
        const [sha, parents, ...message] = entry.trimStart().split("\n");
        return { sha: sha!, parents: parents!.split(" ").filter(Boolean), message: message.join("\n"), files: git("diff-tree", "--root", "--no-commit-id", "--name-only", "-r", sha!).split("\n") };
      });
    }
  }
  const verdict = decide({ attempt: ci.run_attempt, conclusion: ci.conclusion, original, confirmed: ci.run_attempt === 2 ? jobs(id, 2) : [], previous: prior && { sha: prior.head_sha, conclusion: prior.conclusion }, commits, onMain, head: ci.head_sha });
  const detail = `Culprit range: ${commits.map(c => c.sha).join(", ") || ci.head_sha}\nFailing step: ${verdict.step ?? "unknown"}\n[CI run](${ci.html_url})\n${verdict.reason}`;
  if (verdict.kind === "confirm") {
    report(existing, marker, `${detail}\nRequested one confirmation of job ${verdict.job}; a green confirmation is reported, never treated as a repaired run.`);
    gh("api", "--method", "POST", `${repo()}/actions/jobs/${verdict.job}/rerun`);
  } else if (verdict.kind === "revert") {
    try {
      git("checkout", "-q", "-B", "sheriff", "origin/main");
      for (const sha of verdict.shas!) git("revert", "--no-commit", sha);
      git("-c", "core.hooksPath=/dev/null", "commit", "-m", `Revert confirmed main CI culprit\n\n${verdict.step}\n${ci.html_url}\n\nSheriff-Reverts: ${verdict.shas!.join(" ")}`);
      git("push", "origin", "HEAD:refs/heads/main");
      report(existing, marker, `${detail}\nReverted as ${git("rev-parse", "HEAD")}.`);
    } catch (error) {
      Bun.spawnSync(["git", "revert", "--abort"]);
      report(existing, marker, `${detail}\nAutomatic revert failed: ${String(error)}`);
      throw error;
    }
  } else if (verdict.kind === "report") report(existing, marker, detail);
}

if (import.meta.main) {
  const id = Number(process.argv[2]);
  if (!Number.isSafeInteger(id) || id <= 0) throw new Error("usage: bun main-red.ts RUN_ID");
  sheriff(id);
}
