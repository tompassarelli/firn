#!/usr/bin/env bash
# Adversarial matrix for session-killing and unmanaged-child launch shapes.
set -uo pipefail
# Hooks run with the managed hook runtime first on PATH; so do their tests.
export PATH="/etc/codex/hooks/runtime:$PATH"

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/session-kill-guard.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/session-kill-guard-test.XXXXXX")"
trap 'rm -rf "${SCRATCH:?}"' EXIT
mkdir -p "$SCRATCH/home/.local/state/north"
ACTIVATION="$SCRATCH/activation.json"

pass=0 fail=0 LAST_OUT=""
set_active() {
  local permission=off
  [ "$1" = true ] && permission=on
  printf '{"schema":"north.agent-activation/v1","catalogDigest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","generationId":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","units":[{"id":"session-kill-guard","kind":"hook","category":"authoring","permission":"%s","active":%s}]}\n' "$permission" "$1" >"$ACTIVATION"
}
set_active true

# run EXPECT DESCRIPTION COMMAND [ENV...]
run() {
  local expect="$1" desc="$2" cmd="$3"; shift 3
  local input out decision ok=0
  input="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$cmd")"
  out="$(printf '%s' "$input" | env -u AGENT_NO_AUTHORING_HOOKS \
    HOME="$SCRATCH/home" NORTH_AGENT_ACTIVATION="$ACTIVATION" \
    NORTH_AGENT_PYTHON=/etc/codex/hooks/runtime/python3 "$@" "$HOOK" 2>&1)"
  LAST_OUT="$out"
  decision="$(python3 -c 'import json,sys
try:
    d = json.loads(sys.argv[1] or "null")
except Exception:
    print("malformed"); raise SystemExit
print((d or {}).get("hookSpecificOutput", {}).get("permissionDecision", "silent"))' "${out:-}")"
  case "$expect" in
    deny)  [ "$decision" = deny ] && ok=1 ;;
    allow) [ "$decision" != deny ] && [ "$decision" != malformed ] && ok=1 ;;
  esac
  if [ "$ok" = 1 ]; then
    pass=$((pass + 1)); printf 'PASS  %-5s  %s\n' "$expect" "$desc"
  else
    fail=$((fail + 1))
    printf 'FAIL  %-5s  %s\n      cmd=%q\n      decision=%s out=%s\n' "$expect" "$desc" "$cmd" "$decision" "$out"
  fi
}

echo '== broadcast kill is denied =='
run deny 'kill -9 -1' 'kill -9 -1'
run deny 'kill -TERM -1' 'kill -TERM -1'
run deny 'kill -s TERM -1' 'kill -s TERM -1'
run deny 'kill -- -1' 'kill -- -1'
run deny 'bare kill -1 (no pid)' 'kill -1'
run deny 'behind sudo' 'sudo kill -9 -1'
run deny 'after separator' 'printf ready && kill -9 -1'
run deny 'on a second line' "$(printf 'printf ready\nkill -9 -1')"
run deny 'in brace group' '{ kill -9 -1; }'

echo '== user-wide sweeps are denied =='
run deny 'pkill -u user' 'pkill -u tom'
run deny 'pkill -U uid' 'pkill -U 1000'
run deny 'pkill -TERM -u user' 'pkill -TERM -u tom'
run deny 'killall -u user' 'killall -u tom'

echo '== compositor / session teardown is denied =='
run deny 'pkill niri' 'pkill niri'
run deny 'pkill -f niri' 'pkill -f niri'
run deny 'killall niri' 'killall niri'
run deny 'loginctl terminate-user' 'loginctl terminate-user tom'
run deny 'loginctl kill-session' 'loginctl kill-session 3'
run deny 'systemctl --user exit' 'systemctl --user exit'
run deny 'systemctl --user stop niri' 'systemctl --user stop niri.service'
run deny 'systemctl --user restart graphical-session' 'systemctl --user restart graphical-session.target'
run deny 'systemctl stop user@' 'sudo systemctl stop user@1000.service'

echo '== unmanaged agent-child launch shapes are denied =='
run deny 'nohup at command position' 'nohup bun /tmp/wake-cljs-migrate.mjs &'
run deny 'setsid at command position' 'setsid node /tmp/wake-cljs-migrate.mjs'
run deny 'disown at command position' 'sleep 1; disown'
run deny 'ordinary background job' 'bun task &'
run deny 'direct Bun /tmp script' 'bun /tmp/wake-cljs-migrate.mjs'
run deny 'direct Node /tmp script' 'node --enable-source-maps /tmp/wake-cljs-migrate.ts'
case "$LAST_OUT" in
  *'run-bounded <duration> -- <command>'*'24h maximum'*'transient cgroup plus PID namespace'*'48G hard ceiling'*)
    pass=$((pass + 1)); echo 'PASS  deny   ownership denial names the bounded compliant move' ;;
  *)
    fail=$((fail + 1)); printf 'FAIL  deny   ownership denial is incomplete (got: %s)\n' "$LAST_OUT" ;;
esac

echo '== session scratchpad scripts run in the foreground (2026-10-06) =='
SP=/tmp/claude-1000/-home-tom-code-smashcraft/f3a82404-e5fe-4e7f-9184-4ef91c01a770/scratchpad
run allow 'heredoc writes a scratchpad script, then runs it in the foreground' "$(cat <<'CMD'
cd /home/tom/code/wisp/worktrees/watch-20261006 && cat > /tmp/claude-1000/-home-tom-code-smashcraft/f3a82404-e5fe-4e7f-9184-4ef91c01a770/scratchpad/menus-edit.ts <<'EOF'
const p = "scripts/wisp/menus.ts";
let s = await Bun.file(p).text();
const rep = (a: string, b: string) => { if (!s.includes(a)) throw new Error("missing: " + a.slice(0, 60)); s = s.replace(a, b); };
rep(`import { dirname, join } from "node:path";`, `import { tmpdir } from "node:os";\nimport { dirname, join } from "node:path";`);
rep(`import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, rmdirSync, writeFileSync } from "node:fs";`,
  `import { existsSync, mkdirSync, readFileSync, readdirSync, renameSync, rmSync, rmdirSync, writeFileSync } from "node:fs";`);
rep(`const Announcement = Schema.Struct({ port: Schema.Int, guid: Schema.String });`,
`const Announcement = Schema.Struct({ port: Schema.Int, guid: Schema.String });

/**
 * One program at a time can listen on a report port. The listener keeps the
 * newest announced address in a file only this user can read, so another
 * Wisp program (\`wisp watch\` beside \`play\` or \`fresh\`) finds the menus too.
 */
export const menuAddressFile = (reportPort: number) => join(process.env["XDG_RUNTIME_DIR"] ?? tmpdir(), \`wisp-menus-\${reportPort}.json\`);
/** The page announces every 2 s; an address file older than this has no listener behind it. */
const ADDRESS_FRESH_MS = 6000;
const AddressRecord = Schema.Struct({ port: Schema.Int, guid: Schema.String, at: Schema.Number });

const keepAddress = (reportPort: number, address: MenuAddress) => {
  try {
    const path = menuAddressFile(reportPort);
    writeFileSync(\`\${path}.new\`, JSON.stringify({ ...address, at: Date.now() }), { mode: 0o600 });
    renameSync(\`\${path}.new\`, path);
  } catch {
    // Without the file, only this listener knows the address.
  }
};

/** The address another listener on the port keeps, while it is fresh. */
export const keptAddress = (reportPort: number, now = Date.now()): MenuAddress | undefined => {
  try {
    const kept = Schema.decodeUnknownOption(AddressRecord)(JSON.parse(readFileSync(menuAddressFile(reportPort), "utf8")));
    return Option.isSome(kept) && now - kept.value.at <= ADDRESS_FRESH_MS ? { port: kept.value.port, guid: kept.value.guid } : undefined;
  } catch {
    return undefined;
  }
};`);
rep(`            latest = { port: announced.value.port, guid: announced.value.guid };
            Deferred.doneUnsafe(first, Effect.succeed(latest));`,
`            latest = { port: announced.value.port, guid: announced.value.guid };
            keepAddress(reportPort, latest);
            Deferred.doneUnsafe(first, Effect.succeed(latest));`);
rep(`/** Finds this client's installed page. No page means the caller may use its ordinary menu controls. */
export const reportedMenus = (reportPort: number | undefined): Effect.Effect<MenuSocket | undefined, MenuFailure, Scope.Scope> => Effect.gen(function*() {
  if (reportPort === undefined) return undefined;
  const reports = yield* listenForMenus(reportPort);
  const address = yield* reports.waitForAddress(3).pipe(Effect.catchTag("MenuFailure", () => Effect.void));
  if (address === undefined) return undefined;
  return yield* connectMenus(address);
});`,
`/**
 * The menus' address: from the page's announcements, or, while another Wisp
 * program listens on the report port, from the address it keeps.
 */
export const menuAddress = (reportPort: number, seconds: number): Effect.Effect<MenuAddress, MenuFailure, Scope.Scope> =>
  listenForMenus(reportPort).pipe(
    Effect.flatMap((reports) => reports.waitForAddress(seconds)),
    Effect.catchTag("MenuFailure", (failure) => {
      if (failure.operation !== "listen for the menu page") return Effect.fail(failure);
      return Effect.gen(function*() {
        const deadline = Date.now() + seconds * 1000;
        while (true) {
          const kept = keptAddress(reportPort);
          if (kept !== undefined) return kept;
          if (Date.now() >= deadline) return yield* Effect.fail(failure);
          yield* Effect.sleep("250 millis");
        }
      });
    }),
  );

/** Finds this client's installed page. No page means the caller may use its ordinary menu controls. */
export const reportedMenus = (reportPort: number | undefined): Effect.Effect<MenuSocket | undefined, MenuFailure, Scope.Scope> => Effect.gen(function*() {
  if (reportPort === undefined) return undefined;
  const address = yield* menuAddress(reportPort, 3).pipe(Effect.catchTag("MenuFailure", () => Effect.void));
  if (address === undefined) return undefined;
  return yield* connectMenus(address);
});`);
await Bun.write(p, s);
EOF
export PATH=/nix/store/g7skjk9lrdnshaxd7px62bchq6yg0bbh-bun-1.3.13/bin:$PATH; bun /tmp/claude-1000/-home-tom-code-smashcraft/f3a82404-e5fe-4e7f-9184-4ef91c01a770/scratchpad/menus-edit.ts && git diff --stat
CMD
)"
run allow 'foreground scratchpad Bun script in a command list' 'export PATH=/nix/store/g7skjk9lrdnshaxd7px62bchq6yg0bbh-bun-1.3.13/bin:$PATH && bun /tmp/claude-1000/-home-tom-code-smashcraft/025c4a93-ad00-4198-9ec6-9ef9a1cccd8e/scratchpad/endframe-patch.ts; echo "patch exit $?"; cd ~/code/smashcraft/worktrees/end-frame-gate-20261006/ts && git diff --stat && git grep -n "end frames differ" -- .. | head -3; mkdir -p build && bun install --frozen-lockfile > build/install.log 2>&1; echo "install exit $?"; bun test test/playable.test.ts > build/pt.log 2>&1; echo "test exit $?"; grep -E " pass$| fail$" build/pt.log'
run allow 'foreground scratchpad Node script' "node $SP/check.mjs"
run deny 'backgrounded scratchpad Bun script' "bun $SP/menus-edit.ts &"
run deny 'nohup scratchpad Bun script' "nohup bun $SP/menus-edit.ts &"
run deny 'setsid scratchpad Node script' "setsid node $SP/check.mjs"
run deny 'scratchpad path that climbs out' "bun $SP/../../../../../wake-cljs-migrate.mjs"
run deny 'claude temp dir outside a scratchpad' 'bun /tmp/claude-1000/-home-tom-code-smashcraft/f3a82404-e5fe-4e7f-9184-4ef91c01a770/other/x.ts'

echo '== scoped signals — the sanctioned alternative — stay allowed =='
run allow 'kill by pid' 'kill 1234'
run allow 'kill -9 by pid' 'kill -9 1234'
run allow 'kill -TERM by pid' 'kill -TERM 1234'
run allow 'SIGHUP to a pid (kill -1 <pid>)' 'kill -1 1234'
run allow 'scoped process group' 'kill -TERM -- -12345'
run allow 'job spec' 'kill %1'
run allow 'kill -l listing' 'kill -l'
run allow 'pkill with unique pattern' 'pkill -f "wrangler dev --port 8788"'
run allow 'pkill -u with pattern is scoped' 'pkill -u tom -f my-dev-server'
run allow 'killall by name' 'killall node'
run allow 'loginctl read-only' 'loginctl list-sessions'
run allow 'systemctl --user status niri' 'systemctl --user status niri.service'
run allow 'systemctl --user restart other unit' 'systemctl --user restart wob.service'
run allow 'systemctl stop a system unit' 'sudo systemctl stop nginx.service'
run allow 'run-bounded owns a background controller' 'run-bounded 30m -- command &'
run allow 'run-bounded owns a temporary Bun script' 'run-bounded 30m -- bun /tmp/wake-cljs-migrate.mjs'
run allow 'foreground ordinary command' 'bun task'
run allow 'ordinary node source outside /tmp' 'node sdk/task.ts'
run allow '&& is not a background operator' 'printf ready && bun task'
run allow 'redirect ampersand is not a background operator' 'bun task > /tmp/task.log 2>&1'

echo '== prose mentions are never invocations =='
run allow 'commit message mentions kill -9 -1' 'git commit -m "guard: refuse kill -9 -1 broadcast"'
run allow 'echo single-quoted' "echo 'kill -9 -1'"
run allow 'echo double-quoted' 'echo "never run pkill -u tom"'
run allow 'quoted detached-command prose' 'echo "nohup bun /tmp/wake-cljs-migrate.mjs &"'
run allow 'heredoc body mentions the phrase' "$(cat <<'EOF'
cat > notes.md <<'MSG'
The incident command was kill -9 -1 via a bare supervisor run.
MSG
EOF
)"
run allow 'heredoc child command is prose' "$(cat <<'EOF'
cat > notes.md <<'MSG'
nohup bun /tmp/wake-cljs-migrate.mjs &
MSG
EOF
)"

echo '== kill-switch =='
run allow 'guards off via env' 'kill -9 -1' AGENT_NO_AUTHORING_HOOKS=1
set_active false
run allow 'UnitId off via activation' 'kill -9 -1'
set_active true
run deny 'UnitId back on via activation' 'kill -9 -1'

echo
printf '== result: %s passed, %s failed ==\n' "$pass" "$fail"
[ "$fail" = 0 ]
