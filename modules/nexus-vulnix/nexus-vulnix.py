import argparse
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def high_findings(report):
    if not isinstance(report, list):
        raise ValueError("vulnix report must be a list")
    findings = set()
    for package in report:
        for cve in package["affected_by"]:
            score = package["cvssv3_basescore"].get(cve)
            if score is None:
                continue
            if not isinstance(score, (int, float)) or isinstance(score, bool) or not math.isfinite(score) or not 0 <= score <= 10:
                raise ValueError("invalid CVSSv3 score")
            if score >= 7:
                findings.add((package["pname"], package["version"], cve))
    return findings


def atomic_json(path, value):
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as file:
        json.dump(value, file, indent=2)
        file.write("\n")
    os.replace(file.name, path)


def run(state, report_file=None):
    state.mkdir(parents=True, exist_ok=True)
    if report_file:
        raw = report_file.read_text()
    else:
        result = subprocess.run(["vulnix", "--system", "--json"], capture_output=True, text=True)
        (state / "scan.stderr").write_text(result.stderr)
        if result.returncode not in (0, 2):
            raise RuntimeError(f"vulnix failed with exit {result.returncode}; see scan.stderr")
        raw = result.stdout
    report = json.loads(raw)
    findings = high_findings(report)
    atomic_json(state / "report.json", report)
    previous = state / "high.json"
    known = {tuple(item) for item in json.loads(previous.read_text())} if previous.exists() else set()
    new = sorted(findings - known)
    if new:
        body = "New high/critical CVSSv3 findings:\n" + "\n".join(f"{name} {version}: {cve}" for name, version, cve in new)
        subprocess.run(["nexus-alert", "urgent", body, f"{os.uname().nodename}: new high/critical vulnerabilities"], check=True)
    atomic_json(previous, sorted(findings))
    print(f"vulnix: {len(findings)} high/critical findings, {len(new)} new; report {state / 'report.json'}")
    return int(bool(findings))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--state", type=Path, default=Path(os.environ.get("STATE_DIRECTORY", "/var/lib/nexus-vulnix")))
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    try:
        return run(args.state, args.report)
    except (ValueError, KeyError, TypeError, OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"vulnix scan failed: {error}", file=sys.stderr)
        subprocess.run(["nexus-alert", "normal", "Weekly vulnerability scan failed; inspect nexus-vulnix.service and its private report directory.", f"{os.uname().nodename}: vulnerability scan failed"], check=True)
        return 2


if __name__ == "__main__":
    sys.exit(main())
