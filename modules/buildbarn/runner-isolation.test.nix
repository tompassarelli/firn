{ pkgs }:

let
  as = user: "${pkgs.util-linux}/bin/setpriv --reuid=${user} --regid=${user} --init-groups";
  identified = import ./test-identity.nix { inherit pkgs; } "host";
in
pkgs.testers.runNixOSTest {
  name = "buildbarn-runner-isolation";

  nodes.host =
    { config, ... }:
    {
      imports = [
        ./default.nix
        identified.install
      ];
      virtualisation = {
        memorySize = 2048;
        diskSize = 4096;
      };
      environment.systemPackages = [
        pkgs.buildbox
        pkgs.socat
        pkgs.strace
      ];
      users = {
        users.agent = {
          isNormalUser = true;
          group = "agent";
        };
        users.operator = {
          isNormalUser = true;
          group = "operator";
        };
        groups.agent = { };
        groups.operator = { };
      };
      myConfig.modules.buildbarn = {
        identifiedWorkers = true;
        storeGeneration = 1;
        identities.host = identified.certificate;
        server = {
          enable = true;
          address = config.networking.primaryIPAddress;
          interface = "eth1";
          casSizeGiB = 1;
        };
        worker = {
          enable = true;
          server = config.networking.primaryIPAddress;
          serverName = "host";
          concurrency = 2;
          cacheSizeGiB = 1;
          runnerUser = true;
          runnerPerSlot = true;
        };
        client = {
          enable = true;
          server = config.networking.primaryIPAddress;
        };
      };
    };

  testScript =
    { nodes, ... }:
    ''
      import shlex
      import time

      slot_users = ["buildbarn-run-0", "buildbarn-run-1"]
      sockets = ["/run/buildbarn-runner-0/runner.sock", "/run/buildbarn-runner-1/runner.sock"]
      units = ["buildbarn-runner-0.service", "buildbarn-runner-1.service", "buildbarn-worker.service"]
      refused = ("Permission denied", "Operation not permitted")
      trexe = (
          "trexe --remote=http://${nodes.host.networking.primaryIPAddress}:8980"
          " --platform-properties=OSFamily=linux --skip-cache-lookup --do-not-cache"
      )


      def journal():
          return host.execute("journalctl --no-pager -u 'buildbarn-*'")[1]


      def command(script, outputs, inputs):
          arguments = [f"--input-path={path}" for path in inputs]
          arguments += [f"--output-path={path}" for path in outputs]
          if outputs:
              arguments.append("--d=/root/outputs")
          return f"cd /root/client && {trexe} {' '.join(arguments)} -- sh -c {shlex.quote(script)}"


      def remote(script, outputs=(), inputs=("input",)):
          host.succeed("rm -rf /root/outputs", "mkdir -p /root/outputs")
          started = time.monotonic()
          status, text = host.execute(f"{command(script, outputs, inputs)} 2>&1")
          assert status == 0, f"an action failed:\n{text}\n{journal()}"
          return time.monotonic() - started


      def background(script, done):
          host.succeed(f"rm -f {done}")
          host.succeed(f"({command(script, (), ('input',))} > {done}.log 2>&1 || true; touch {done}) > /dev/null 2>&1 &")


      def output(name):
          return host.succeed(f"cat /root/outputs/{name}")


      def process(pattern):
          pid = host.wait_until_succeeds(f"pgrep -f {shlex.quote(pattern)}", timeout=60).split()[0]
          return pid, host.succeed(f"stat -c %U /proc/{pid}").strip()


      def occupy(seconds):
          background(f"sleep {seconds}", f"/root/occupy-{seconds}")
          return process(f"^sleep {seconds}$")


      def probes(lines):
          return "\n".join(
              f"result=$({probe} 2>&1); echo \"{name}|$?|\"$result >> report" for name, probe in lines
          )


      def assert_refused(report, expected):
          seen = {}
          for line in report.splitlines():
              name, status, message = line.split("|", 2)
              seen[name] = (status, message)
              print(f"{name}: exit {status}: {message}")
          assert set(seen) == set(expected), f"probes ran: {sorted(seen)}"
          for name, (status, message) in seen.items():
              assert status != "0" and any(text in message for text in refused), f"{name} was not refused: {message}"


      host.start()
      host.wait_for_unit("multi-user.target")
      for unit in units:
          host.wait_for_unit(unit, timeout=60)
      assert int(host.succeed("sysctl -n kernel.yama.ptrace_scope")) >= 1
      host.succeed("mkdir -p /root/client", "printf 'original bytes\\n' > /root/client/input")
      digest = host.succeed("sha256sum < /root/client/input").strip()
      print(f"an empty action takes {remote('true'):.2f} s")

      with subtest("the action cache was emptied for generation 1 before the store started, and only root writes the generation"):
          emptied = int(host.succeed("systemctl show -P ExecMainExitTimestampMonotonic buildbarn-action-cache-generation.service"))
          stored = int(host.succeed("systemctl show -P ExecMainStartTimestampMonotonic buildbarn-storage.service"))
          assert 0 < emptied <= stored, f"emptied at {emptied}, store started at {stored}"
          print(host.succeed("journalctl --no-pager -o cat -u buildbarn-action-cache-generation | grep '^store generation none -> 1: '"))
          attempts = [
              "echo 9 > /etc/buildbarn/store-generation",
              "mv /etc/buildbarn/store-generation /etc/buildbarn/moved",
              "touch /etc/buildbarn/added",
          ]
          remote(
              "\n".join(f"({attempt}) 2>> refusals; echo $? >> statuses" for attempt in attempts) + "\nid -un > who",
              outputs=("refusals", "statuses", "who"),
          )
          print(f"{output('who').strip()} in an action on the generation file:\n{output('refusals')}")
          assert output("who").strip() in slot_users, output("who")
          statuses = output("statuses").split()
          assert len(statuses) == len(attempts) and "0" not in statuses, statuses
          for user in slot_users + ["agent"]:
              for attempt in attempts:
                  host.fail(
                      f"${pkgs.util-linux}/bin/setpriv --reuid={user} --regid={user} --init-groups sh -c {shlex.quote(attempt)}"
                  )
          host.succeed(
              "test \"$(cat /etc/buildbarn/store-generation)\" = 1",
              "test ! -e /etc/buildbarn/moved",
              "test ! -e /etc/buildbarn/added",
          )

      with subtest("an action cannot touch the files or the processes of one running beside it"):
          background(
              "echo slot-secret > secret; echo private > /tmp/beside; echo private > /dev/shm/beside; sleep 3141",
              "/root/beside",
          )
          beside, beside_user = process("^sleep 3141$")
          directory = host.succeed(f"readlink /proc/{beside}/cwd").strip()
          assert beside_user in slot_users, beside_user
          lines = [
              ("create", f"touch {directory}/planted"),
              ("rename", f"mv {directory}/input {directory}/renamed"),
              ("delete", f"rm -f {directory}/input"),
              ("list", f"ls {directory}"),
              ("create-through-proc", f"touch /proc/{beside}/cwd/planted"),
              ("temporary-file", f"cat /proc/{beside}/root/tmp/beside"),
              ("shared-memory", f"cat /proc/{beside}/root/dev/shm/beside"),
              ("signal", f"kill -9 {beside}"),
              ("trace", f"strace -o /dev/null -p {beside}"),
              ("memory", f"head -c 1 /proc/{beside}/mem"),
              ("own-runner-trace", "strace -o /dev/null -p $PPID"),
              ("own-runner-memory", "head -c 1 /proc/$PPID/mem"),
              ("worker-key", "cat /var/lib/buildbarn/identity/key.pem"),
          ] + [
              (f"socket-{number}", f"socat -u OPEN:/dev/null UNIX-CONNECT:{path}")
              for number, path in enumerate(sockets)
          ]
          remote(
              f"{probes(lines)}\nid -un > who\nls -A /tmp /dev/shm > visible 2>&1",
              outputs=("report", "who", "visible"),
          )
          prober = output("who").strip()
          assert prober in slot_users and prober != beside_user, f"{prober} probed {beside_user}"
          assert_refused(output("report"), [name for name, _ in lines])
          assert "beside" not in output("visible"), output("visible")
          host.succeed(
              f"test -d /proc/{beside}",
              f"test \"$(sha256sum < {directory}/input)\" = '{digest}'",
              f"test ! -e {directory}/planted",
              f"test ! -e {directory}/renamed",
          )

      with subtest("nothing an action leaves is there when the next one starts in its slot"):
          leave = "\n".join([
              "(setsid sleep 2718 > /dev/null 2>&1 &)",
              "(setsid sh -c 'while :; do sleep 2719; done' > /dev/null 2>&1 &)",
              "for directory in /tmp /var/tmp /dev/shm; do echo left > $directory/left; done",
              "mkdir /tmp/closed; echo left > /tmp/closed/left; chmod 0000 /tmp/closed",
              "ipcmk --shmem 4096 > /dev/null",
              "sleep 8",
          ])
          background(leave, "/root/leave")
          daemon, leaver = process("^sleep 2718$")
          respawned, _ = process("^sleep 2719$")
          assert leaver == prober, f"the leaving action ran as {leaver}"
          host.wait_until_succeeds("test -e /root/leave", timeout=60)
          print(host.succeed("cat /root/leave.log"))
          host.succeed(f"test ! -d /proc/{daemon}", f"test ! -d /proc/{respawned}")
          runner = host.succeed(f"systemctl show -P MainPID buildbarn-runner-{leaver[-1]}.service").strip()
          assert host.succeed(f"pgrep -u {leaver}").split() == [runner], "the slot's user runs more than its runner"
          remote(
              "id -un > who; ls -A /tmp /var/tmp /dev/shm > left 2>&1; ipcs --shmem | grep -c '^0x' > segments; true",
              outputs=("who", "left", "segments"),
          )
          assert output("who").strip() == leaver, output("who")
          left = [line for line in output("left").splitlines() if line and not line.endswith(":")]
          assert left == [], f"the next action saw {left}"
          assert output("segments").strip() == "0", output("segments")

      with subtest("an output path that leads into another slot's directory uploads nothing from it"):
          for script, declared in [
              (f"ln -s {directory}/secret link", "link"),
              (f"rmdir parent; ln -s {directory} parent", "parent/secret"),
          ]:
              host.succeed("rm -rf /root/outputs", "mkdir -p /root/outputs")
              status, text = host.execute(f"{command(script, (declared,), ('input',))} 2>&1")
              print(f"declared output {declared}: exit {status}\n{text}\n{host.succeed('ls -lR /root/outputs')}")
              host.fail("grep -r slot-secret /root/outputs")
              host.succeed(f"test \"$(cat {directory}/secret)\" = slot-secret")

      with subtest("what an input costs a slot that has not fetched it"):
          host.succeed(
              "mkdir -p /root/client/tree",
              "for n in $(seq 400); do head -c 262144 /dev/urandom > /root/client/tree/$n; done",
          )
          read = "cat tree/* | sha256sum > sum; id -un > who"
          first = remote(read, outputs=("sum", "who"), inputs=("tree",))
          assert output("who").strip() == prober, output("who")
          again = remote(read, outputs=("sum", "who"), inputs=("tree",))
          assert output("who").strip() == prober, output("who")
          host.succeed(f"kill {beside}")
          host.wait_until_succeeds("test -e /root/beside", timeout=60)
          holders = dict([occupy(3142)[::-1], occupy(3143)[::-1]])
          assert set(holders) == set(slot_users), holders
          host.succeed(f"kill {holders[beside_user]}")
          host.wait_until_fails(f"pgrep -u {beside_user} -x sleep", timeout=60)
          other = remote(read, outputs=("sum", "who"), inputs=("tree",))
          assert output("who").strip() == beside_user, output("who")
          print(
              f"100 MiB of inputs in 400 files: {first:.2f} s uploaded and fetched,"
              f" {again:.2f} s again in that slot, {other:.2f} s first in the other slot"
          )
          host.succeed(f"kill {holders[prober]}")

      with subtest("a runner its own action kills comes back closed and its slot serves"):
          host.wait_until_fails(f"pgrep -x sleep -u {','.join(slot_users)}", timeout=60)
          status, text = host.execute(f"{command('kill -9 $PPID; sleep 5', (), ('input',))} 2>&1")
          print(f"the action that killed its runner exited {status}:\n{text}")
          assert status != 0, text
          host.wait_until_succeeds(
              f"test \"$(systemctl show -P NRestarts {units[0]} {units[1]} | sort | tr -d '\\n')\" = 01", timeout=60
          )
          for unit in units:
              host.wait_until_succeeds(f"systemctl is-active {unit}", timeout=120)
          for path in sockets:
              host.succeed(f"test \"$(stat -c '%a %U %G' $(dirname {path}))\" = '700 buildbarn buildbarn'")
          holders = dict([occupy(3144)[::-1], occupy(3145)[::-1]])
          assert set(holders) == set(slot_users), holders
          host.succeed(f"kill {' '.join(holders.values())}")

      with subtest("an action in either slot reaches no listener and no inner socket of the store"):
          address = "${nodes.host.networking.primaryIPAddress}"
          inner = ["/run/buildbarn-storage/storage.sock", "/run/buildbarn-scheduler/client.sock"]
          reaches = [
              (f"{target}:{port}", f"TCP:{target}:{port},connect-timeout=3")
              for target in [address, "127.0.0.1"]
              for port in [8980, 8983, 8984]
          ] + [(path, f"UNIX-CONNECT:{path}") for path in inner]
          reach = "\n".join(
              f"socat -u OPEN:/dev/null {to} 2>> refusals; echo \"{name} $?\" >> statuses" for name, to in reaches
          )
          for port in [8980, 8983, 8984]:
              host.succeed(f"socat -u OPEN:/dev/null TCP:{address}:{port},connect-timeout=3")
          for path in inner:
              host.succeed(f"socat -u OPEN:/dev/null UNIX-CONNECT:{path}")
          for number, user in enumerate(slot_users):
              host.wait_until_fails(f"pgrep -x sleep -u {','.join(slot_users)}", timeout=60)
              holders = dict([occupy(3150 + 2 * number)[::-1], occupy(3151 + 2 * number)[::-1]])
              assert set(holders) == set(slot_users), holders
              host.succeed(f"kill {holders[user]}")
              host.wait_until_fails(f"pgrep -u {user} -x sleep", timeout=60)
              control = "\n".join([
                  "socat UNIX-LISTEN:/tmp/control.sock OPEN:/dev/null &",
                  "tries=0; until [ -S /tmp/control.sock ] || [ $tries -ge 50 ]; do tries=$((tries + 1)); sleep 0.1; done",
                  "socat -u OPEN:/dev/null UNIX-CONNECT:/tmp/control.sock; echo \"control $?\" > statuses",
              ])
              remote(f"{control}\n{reach}\nid -un > who", outputs=("refusals", "statuses", "who"))
              assert output("who").strip() == user, output("who")
              print(f"what an action of {user} reaches:\n{output('statuses')}{output('refusals')}")
              statuses = output("statuses").splitlines()
              assert statuses[0] == "control 0", f"the action's own connection failed: {statuses}"
              assert len(statuses) == 1 + len(reaches) and all(line.endswith(" 1") for line in statuses[1:]), statuses
              errors = [line for line in output("refusals").splitlines() if " E " in line]
              assert len(errors) == len(reaches), output("refusals")
              for line in errors:
                  assert line.endswith(("Connection refused", "Network is unreachable", "Permission denied")), line
              host.succeed(f"kill {' '.join(pid for holder, pid in holders.items() if holder != user)}")
              for path in inner:
                  message = host.fail(
                      f"${pkgs.util-linux}/bin/setpriv --reuid={user} --regid={user} --init-groups"
                      f" socat -u OPEN:/dev/null UNIX-CONNECT:{path} 2>&1"
                  )
                  assert "Permission denied" in message, message

      with subtest("only the worker opens a runner's socket"):
          for path in sockets:
              host.succeed(f"${as "buildbarn"} socat -u OPEN:/dev/null UNIX-CONNECT:{path}")
              for user in slot_users + ["agent", "operator"]:
                  message = host.fail(
                      f"${pkgs.util-linux}/bin/setpriv --reuid={user} --regid={user} --init-groups"
                      f" socat -u OPEN:/dev/null UNIX-CONNECT:{path} 2>&1"
                  )
                  print(f"{user} on {path}: {message.strip()}")
                  assert "Permission denied" in message, message

      with subtest("a link a slot's user puts where its runner's socket goes is refused and its target keeps its owner"):
          close = "${nodes.host.systemd.services.buildbarn-runner-0.serviceConfig.ExecStartPost}".lstrip("+").split()[0]
          host.succeed(
              "systemd-run --unit=link-target socat UNIX-LISTEN:/run/link-target.sock,fork OPEN:/dev/null",
              "install -d -o buildbarn-run-0 -g buildbarn-run-0 -m 0750 /run/planted",
          )
          host.wait_until_succeeds("test -S /run/link-target.sock", timeout=60)
          before = host.succeed("stat -c '%a %U %G' /run/link-target.sock")
          host.succeed("${as "buildbarn-run-0"} ln -s /run/link-target.sock /run/planted/runner.sock")
          print(f"closing a planted link: {host.fail(f'{close} planted 2>&1').strip()}")
          assert host.succeed("stat -c '%a %U %G' /run/link-target.sock") == before, before
          host.succeed("test \"$(stat -c '%a %U' /run/planted)\" = '700 buildbarn'")
          host.fail("${as "buildbarn-run-0"} rm /run/planted/runner.sock")

      for unit in units:
          host.succeed(f"systemctl is-active {unit}")
    '';
}
