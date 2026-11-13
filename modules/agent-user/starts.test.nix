{
  pkgs,
  package,
  caller ? true,
}:

pkgs.testers.runNixOSTest {
  name = "agent-local-starts${if caller then "" else "-unchecked"}";

  nodes.host =
    { lib, ... }:
    {
      imports = [ ./default.nix ];
      options.myConfig.modules.users.username = lib.mkOption { type = lib.types.str; };
      config = {
        myConfig.modules.users.username = "operator";
        myConfig.modules.agent-user = {
          enable = true;
          gid = 1500;
          localStarts = {
            enable = true;
            inherit package caller;
          };
        };
        users.users.operator = {
          isNormalUser = true;
          uid = 1000;
          homeMode = "0700";
          linger = true;
        };
        security.polkit.enable = true;
        environment.systemPackages = [ pkgs.strace ];
      };
    };

  testScript = ''
    import json
    import re
    import shlex

    requests = "/var/lib/north-agent-starts"
    spool = "/home/operator/.local/state/north/fleet/spool"
    records = "/home/agent/.local/state/north/agent-starts"


    def worker(command):
        status, output = host.execute(
            "systemd-run --quiet --machine=operator@.host --user --pipe --wait --collect -- "
            f"/run/current-system/sw/bin/sh -c {shlex.quote(command)} 2>&1"
        )
        print(f"worker command {command!r} exited {status}:\n{output}")
        return status, output


    def request(name, **extra):
        return json.dumps({"name": name, "account": "a", "cwd": "/home/agent/work/one", "brief": "/home/agent/briefs/one.md", **extra})


    def admitted(file, body):
        host.succeed(f"runuser -u operator -- sh -c {shlex.quote(f'cat > {requests}/{file}')} <<'EOF'\n{body}\nEOF")


    host.start()
    host.wait_for_unit("multi-user.target")
    host.wait_for_unit("user@1000.service")
    host.wait_for_unit("north-agent-starts.service")
    assert host.succeed(f"stat -c '%U %a' {requests}").strip() == "operator 700", "the request directory is not the operator's alone"
    unit = host.succeed("systemctl cat north-agent-starts.service")
    found = re.search(r"--entry (\S+)", unit)
    assert found is not None, f"the starter unit names no entry:\n{unit}"
    entry = found.group(1)
    starter = host.succeed("systemctl show -P MainPID north-agent-starts.service").strip()

    worker(f"mkdir -p {spool}/sessions/w-lead && printf '%s\\n' {shlex.quote(request('f-spooled'))} > {spool}/sessions/w-lead/3.start")
    admitted("1.start", request("f-one"))
    admitted("2.start", request("f-bad", command="id"))
    try:
        host.wait_until_succeeds(f"test -f {records}/f-one.json", timeout=60)
    except Exception:
        print(host.execute("journalctl -b --no-pager -u north-agent-starts.service; journalctl -b --no-pager _UID=1001; ps -eo pid,user,stat,wchan:24,args | grep -e north -e machinectl; ls -laR /home/agent/.local 2>&1")[1])
        raise
    host.succeed(f"test \"$(stat -c %U {records}/f-one.json)\" = agent")
    assert json.loads(host.succeed(f"cat {records}/f-one.json")) == json.loads(request("f-one")), "the entry recorded another request than the one written"
    host.wait_until_succeeds(f"test -f {requests}/rejected/2.start", timeout=30)
    host.succeed(f"test ! -e {records}/f-bad.json")
    assert host.execute(f"test -e {records}/f-spooled.json")[0] != 0, "a request a worker left in its own spool location started a session"

    status, output = worker("systemd-run --machine=agent@.host --user --no-ask-password --pipe --wait id -u")
    assert status != 0 and "1001" not in output, "a worker command started a process as the agent through systemd-run"
    status, output = worker(f"printf '%s\\n' {shlex.quote(request('f-worker'))} | ${pkgs.coreutils}/bin/timeout 20 ${pkgs.systemd}/bin/machinectl --quiet --no-ask-password shell agent@.host {entry}")
    host.sleep(2)
    assert "Access denied" in output and host.execute(f"test -e {records}/f-worker.json")[0] != 0, "a worker command's machinectl shell of the fixed entry ran it as the agent"
    status, output = worker("${pkgs.systemd}/bin/busctl call --system org.freedesktop.systemd1 /org/freedesktop/systemd1 org.freedesktop.systemd1.Manager AttachProcessesToUnit ssau north-agent-starts.service / 1 $$")
    assert status != 0, "a worker command attached itself to the starter unit"
    status, output = worker("echo $$ > /sys/fs/cgroup/system.slice/north-agent-starts.service/cgroup.procs")
    assert status != 0, "a worker command wrote itself into the starter unit's cgroup"
    status, output = worker(f"${pkgs.strace}/bin/strace -e trace=none -p {starter} & sleep 2; kill $! 2>/dev/null; wait $!")
    assert "Operation not permitted" in output, "a worker command attached a tracer to the starter"
    status, output = worker(f"exec 3</proc/{starter}/mem")
    assert status != 0, "a worker command opened the starter's memory"
    host.succeed(f"test \"$(systemctl show -P MainPID north-agent-starts.service)\" = {starter}")
  '';
}
