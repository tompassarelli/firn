#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/bin"
cat > "$work/bin/nexus-alert" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$ALERT_LOG"
SH
cat > "$work/bin/vulnix" <<'SH'
#!/usr/bin/env bash
cat "$SCAN_REPORT"
exit "${SCAN_RC:-2}"
SH
chmod +x "$work/bin/nexus-alert" "$work/bin/vulnix"
export PATH="$work/bin:$PATH" ALERT_LOG="$work/alerts"
python3 - "$here" "$work" <<'PYTHON'
import json
import os
from pathlib import Path
import subprocess
import sys
here, work = map(Path, sys.argv[1:])
report = work / "fixture.json"
state = work / "state"
os.environ["SCAN_REPORT"] = str(report)
package = {"pname":"fixture", "version":"1", "affected_by":["CVE-HIGH","CVE-MEDIUM"], "whitelisted":["CVE-MASKED"], "cvssv3_basescore":{"CVE-HIGH":7.0,"CVE-MEDIUM":6.9,"CVE-MASKED":10.0}}
def scan(expected):
    result = subprocess.run([sys.executable, str(here / "nexus-vulnix.py"), "--state", str(state)])
    assert result.returncode == expected, result.returncode
report.write_text(json.dumps([package]))
scan(1)
assert json.loads((state / "report.json").read_text()) == [package]
assert json.loads((state / "high.json").read_text()) == [["fixture","1","CVE-HIGH"]]
assert len((work / "alerts").read_text().splitlines()) == 2
scan(1)
assert len((work / "alerts").read_text().splitlines()) == 2
package["affected_by"].append("CVE-CRITICAL")
package["cvssv3_basescore"]["CVE-CRITICAL"] = 9.8
report.write_text(json.dumps([package]))
scan(1)
assert "CVE-CRITICAL" in (work / "alerts").read_text()
report.write_text("[]")
scan(0)
assert json.loads((state / "high.json").read_text()) == []
report.write_text("not-json")
scan(2)
assert "scan failed" in (work / "alerts").read_text()
print("ok: vulnix JSON schema reference journey: report, CVSS threshold, masked exclusion, new findings, dedupe, recovery, scan failure")
PYTHON
