{ pkgs }:

let
  workerRoot = "/var/lib/buildbarn/worker";
  buildDirectory = "${workerRoot}/build";
  cacheDirectory = "${workerRoot}/cache";
  marker = "/var/lib/buildbarn/build-directory-reset";
  as = user: "${pkgs.util-linux}/bin/setpriv --reuid=${user} --regid=${user} --init-groups";
in
pkgs.testers.runNixOSTest {
  name = "buildbarn-runner-user";

  nodes.host =
    { config, ... }:
    {
      imports = [ ./default.nix ];
      virtualisation = {
        memorySize = 2048;
        diskSize = 4096;
      };
      environment.systemPackages = [ pkgs.buildbox ];
      myConfig.modules.buildbarn = {
        server = {
          enable = true;
          address = config.networking.primaryIPAddress;
          interface = "eth1";
          casSizeGiB = 1;
        };
        worker = {
          enable = true;
          server = config.networking.primaryIPAddress;
          concurrency = 2;
          cacheSizeGiB = 1;
          runnerUser = true;
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

      units = ["buildbarn-runner.service", "buildbarn-worker.service"]
      trexe = (
          "trexe --remote=http://${nodes.host.networking.primaryIPAddress}:8980"
          " --platform-properties=OSFamily=linux --skip-cache-lookup --do-not-cache"
      )


      def journal():
          return host.execute(
              "journalctl --no-pager -u buildbarn-build-directory-reset"
              " -u buildbarn-runner -u buildbarn-worker"
          )[1]


      def settled(phase):
          try:
              for unit in units:
                  host.wait_for_unit(unit, timeout=60)
              since = {u: host.succeed(f"systemctl show -P ActiveEnterTimestampMonotonic {u}") for u in units}
              host.sleep(7)
              for unit in units:
                  host.succeed(f"systemctl is-active {unit}")
                  assert host.succeed(f"systemctl show -P ActiveEnterTimestampMonotonic {unit}") == since[unit], f"{unit} restarted"
          except Exception:
              print(f"journal after {phase}:\n{journal()}")
              raise
          host.succeed(
              "test \"$(stat -c '%a %U %G' ${buildDirectory})\" = '2770 buildbarn-run buildbarn-run'",
              "test \"$(stat -c '%U %G' ${marker})\" = 'root root'",
              "! ${as "buildbarn"} touch /var/lib/buildbarn/worker-probe",
              "! ${as "buildbarn-run"} ls ${cacheDirectory}",
          )


      def reset_from(mode, owner):
          host.succeed(
              "systemctl stop buildbarn-worker buildbarn-runner",
              "rm -f ${marker}",
              f"chown {owner} ${buildDirectory}",
              f"chmod {mode} ${buildDirectory}",
              "mkdir -p ${buildDirectory}/leftover/sub",
              "echo old > ${buildDirectory}/leftover/sub/file",
              "chown -R buildbarn:buildbarn ${buildDirectory}/leftover",
              "chmod 0444 ${buildDirectory}/leftover/sub/file",
              "chmod 0555 ${buildDirectory}/leftover/sub",
              "echo old > ${buildDirectory}/stray",
              "chown buildbarn-run:buildbarn-run ${buildDirectory}/stray",
              "systemctl start buildbarn-worker",
          )
          settled(f"a reset from {mode} {owner}")
          host.succeed("test ! -e ${buildDirectory}/leftover", "test ! -e ${buildDirectory}/stray")


      def remote(script, *args):
          return host.execute(
              f"cd /root/client && {trexe} {' '.join(args)} -- sh -c {shlex.quote(script)} 2>&1"
          )


      def cached():
          return host.succeed("find ${cacheDirectory} -type f -print0 | xargs -0r sha256sum").splitlines()


      host.start()
      settled("boot")

      host.succeed("systemctl restart buildbarn-runner")
      settled("a runner restart with the marker present")

      reset_from("755", "buildbarn:buildbarn")
      reset_from("2770", "buildbarn-run:buildbarn-run")

      host.succeed("mkdir -p /root/client /root/outputs", "printf 'original bytes\\n' > /root/client/input")
      digest = host.succeed("sha256sum /root/client/input | cut -d' ' -f1").strip()
      assert cached() == [], f"the worker cache holds files before the first action: {cached()}"

      status, output = remote("chmod 0666 input; echo tampered >> input", "--input-path=input")
      print(f"tampering action exited {status}:\n{output}")
      stored = cached()
      assert len(stored) == 1 and stored[0].startswith(digest), f"the cached input changed: {stored}"
      cache_file = stored[0].split(None, 1)[1]
      print(host.succeed(f"stat -c '%A %U:%G %h' {cache_file}"))
      host.succeed(
          f"test \"$(stat -c %U {cache_file})\" = buildbarn",
          f"test -z \"$(find {cache_file} -perm /022)\"",
      )

      status, output = remote(
          "cat input > copy; ls ${cacheDirectory} > /dev/null 2>&1; echo $? > ls-status",
          "--input-path=input", "--output-path=copy", "--output-path=ls-status", "--d=/root/outputs",
      )
      assert status == 0, f"reading action failed:\n{output}\n{journal()}"
      host.succeed(f"test \"$(sha256sum < /root/outputs/copy | cut -d' ' -f1)\" = {digest}")
      host.succeed("test \"$(cat /root/outputs/ls-status)\" != 0")
      host.fail("journalctl --no-pager -u buildbarn-runner -u buildbarn-worker | grep -F 'Failed to add cached file'")
    '';
}
