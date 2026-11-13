{ pkgs }:

let
  inherit (pkgs) lib;
  identity = import ./test-identity.nix { inherit pkgs; };
  listed = lib.genAttrs [ "store" "builder" ] (name: (identity name).certificate);
  storeCertificate = pkgs.writeText "store.pem" listed.store;
  key = "/var/lib/buildbarn/identity/key.pem";
  certificate = "/var/lib/buildbarn/identity/cert.pem";
  buildDirectory = "/var/lib/buildbarn/worker/build";
  actionCache = "/var/lib/buildbarn/storage/ac";
  generationRecord = "/var/lib/buildbarn/action-cache-generation";
  generationFile = "/etc/buildbarn/store-generation";
  emptying = "buildbarn-action-cache-generation";
  runnerSocket = "/run/buildbarn-runner/runner.sock";
  sockets = [
    "/run/buildbarn-storage/storage.sock"
    "/run/buildbarn-scheduler/client.sock"
  ];
  ports = [
    8980
    8983
    8984
  ];
  remoteExecution = "-import-path ${pkgs.buildbox.src}/protos -proto build/bazel/remote/execution/v2/remote_execution.proto";
  workerProtocol = pkgs.writeTextDir "remoteworker.proto" ''
    syntax = "proto3";
    package buildbarn.remoteworker;
    service OperationQueue {
      rpc Synchronize(SynchronizeRequest) returns (SynchronizeResponse);
    }
    message Empty {}
    message Platform {
      message Property {
        string name = 1;
        string value = 2;
      }
      repeated Property properties = 1;
    }
    message CurrentState {
      Empty idle = 1;
    }
    message SynchronizeRequest {
      map<string, string> worker_id = 1;
      string instance_name_prefix = 2;
      Platform platform = 3;
      CurrentState current_state = 4;
    }
    message SynchronizeResponse {}
  '';
  setpriv = "${pkgs.util-linux}/bin/setpriv";
  as = user: "${setpriv} --reuid=${user} --regid=${user} --init-groups";
  connect = socket: "socat -u OPEN:/dev/null UNIX-CONNECT:${socket}";

  common = {
    imports = [ ./default.nix ];
    virtualisation.diskSize = 4096;
    environment.systemPackages = [
      pkgs.buildbox
      pkgs.grpcurl
      pkgs.socat
    ];
    users = {
      users.agent = {
        isNormalUser = true;
        group = "agent";
      };
      groups.agent = { };
    };
    myConfig.modules.buildbarn = {
      identifiedWorkers = true;
      storeGeneration = lib.mkDefault 1;
      identities = listed;
    };
  };
  worker = nodes: {
    enable = true;
    server = nodes.store.networking.primaryIPAddress;
    serverName = "store";
    concurrency = 2;
    cacheSizeGiB = 1;
    runnerUser = true;
  };
in
pkgs.testers.runNixOSTest {
  name = "buildbarn-store-writes";

  nodes = {
    store =
      { config, nodes, ... }:
      {
        imports = [
          common
          (identity "store").install
        ];
        virtualisation.memorySize = 2048;
        myConfig.modules.buildbarn = {
          server = {
            enable = true;
            address = config.networking.primaryIPAddress;
            interface = "eth1";
            casSizeGiB = 1;
          };
          worker = worker nodes;
          client = {
            enable = true;
            server = config.networking.primaryIPAddress;
          };
        };
        specialisation.generation2.configuration.myConfig.modules.buildbarn.storeGeneration = 2;
      };
    builder =
      { nodes, ... }:
      {
        imports = [
          common
          (identity "builder").install
        ];
        virtualisation.memorySize = 2048;
        myConfig.modules.buildbarn.worker = worker nodes;
      };
    rogue =
      { nodes, ... }:
      {
        imports = [ common ];
        myConfig.modules.buildbarn.worker = worker nodes;
      };
    client =
      { nodes, ... }:
      {
        imports = [ common ];
        myConfig.modules.buildbarn.client = {
          enable = true;
          server = nodes.store.networking.primaryIPAddress;
        };
      };
  };

  testScript =
    { nodes, ... }:
    ''
      import json
      import shlex

      address = "${nodes.store.networking.primaryIPAddress}"
      trexe = f"trexe --remote=http://{address}:8980 --platform-properties=OSFamily=linux"
      uncached = "--skip-cache-lookup --do-not-cache"
      forged = "f" * 64
      own_key = "-cert ${certificate} -key ${key}"
      workers = "systemctl {} buildbarn-worker buildbarn-runner"


      def run(machine, script, *args, limit=120):
          return machine.execute(
              f"cd /root/work && timeout {limit} {trexe} --input-path=input {' '.join(args)}"
              f" -- sh -c {shlex.quote(script)} 2>&1"
          )


      def call(machine, transport, port, protocol, method, request):
          status, output = machine.execute(
              f"grpcurl {transport} {protocol} -d {shlex.quote(json.dumps(request))}"
              f" store:{port} {method} 2>&1"
          )
          print(f"{machine.name} -> store:{port} {method} ({transport or 'no flag'}): exit {status}\n{output}")
          return status, output


      def action_cache(machine, transport, port, method, **fields):
          request = {"action_digest": {"hash": forged, "size_bytes": 1}} | fields
          return call(
              machine, transport, port, "${remoteExecution}",
              f"build.bazel.remote.execution.v2.ActionCache/{method}", request,
          )


      def register(machine, transport):
          return call(
              machine, transport, 8983, "-import-path ${workerProtocol} -proto remoteworker.proto",
              "buildbarn.remoteworker.OperationQueue/Synchronize",
              {
                  "worker_id": {"hostname": f"probe-{machine.name}"},
                  "instance_name_prefix": "probe",
                  "platform": {"properties": [{"name": "OSFamily", "value": "linux"}]},
                  "current_state": {"idle": {}},
              },
          )


      def read_result():
          for _ in range(30):
              status, output = action_cache(client, "-plaintext", 8980, "GetActionResult")
              if "Unavailable" not in output:
                  return status, output
              client.sleep(1)
          raise Exception(f"the store did not answer:\n{output}")


      def emptied():
          return store.succeed("journalctl --no-pager -o cat -u ${emptying} | grep '^store generation '").splitlines()


      def refused(result, *codes):
          status, output = result
          assert status != 0 and any(code in output for code in codes), f"not refused with {codes}:\n{output}"


      start_all()
      for unit in ["buildbarn-storage", "buildbarn-scheduler", "buildbarn-frontend", "buildbarn-worker"]:
          store.wait_for_unit(unit)
      builder.wait_for_unit("buildbarn-worker")
      rogue.wait_for_unit("buildbarn-identity")
      client.wait_for_unit("multi-user.target")
      for machine in [store, builder, client]:
          machine.succeed("mkdir -p /root/work", "printf 'the same input\\n' > /root/work/input")

      with subtest("the store host listens on the three ports only, and its inner sockets open for the service user only"):
          for machine, units in [(store, ["frontend", "scheduler", "worker"]), (builder, ["worker"])]:
              for unit in units:
                  for dependency in ["After", "Requires"]:
                      machine.succeed(
                          f"systemctl show -P {dependency} buildbarn-{unit}.service | tr ' ' '\n' | grep -qx buildbarn-identity.service"
                      )
          listening = store.succeed("ss -ltnpH | grep -F bb_ | grep -o ':[0-9]* ' | tr -d ': ' | sort -u").split()
          assert listening == ${builtins.toJSON (map toString ports)}, f"Buildbarn listens on {listening}"
          assert builder.succeed("ss -ltnpH | grep -cF bb_ || true").strip() == "0"
          for socket in ${builtins.toJSON sockets}:
              store.succeed(f"${as "buildbarn"} ${connect "{socket}"}")
              for user, group in [("agent", "agent"), ("buildbarn-run", "buildbarn-run"), ("nobody", "nogroup")]:
                  print(store.fail(f"${setpriv} --reuid={user} --regid={group} --clear-groups ${connect "{socket}"} 2>&1"))
          for machine in [store, builder]:
              machine.succeed("${setpriv} --reuid=buildbarn --regid=buildbarn --groups=buildbarn-run ${connect runnerSocket}")
              print(machine.fail("${as "agent"} ${connect runnerSocket} 2>&1"))
              status, output = machine.execute("${as "buildbarn-run"} ${connect runnerSocket} 2>&1")
              print(f"observation: the runner user opening the runner's own socket on {machine.name} exits {status} {output}")

      with subtest("a client cannot write an action result, a holder of a listed key can"):
          refused(action_cache(client, "-plaintext", 8980, "UpdateActionResult", action_result={"exit_code": 7}), "PermissionDenied")
          refused(action_cache(client, "-plaintext", 8980, "GetActionResult"), "NotFound")
          refused(action_cache(client, "-cacert ${storeCertificate}", 8984, "UpdateActionResult", action_result={"exit_code": 7}), "Unauthenticated")
          refused(action_cache(client, "-plaintext", 8984, "UpdateActionResult", action_result={"exit_code": 7}), "Failed to dial", "Unavailable")
          refused(action_cache(rogue, "-cacert ${storeCertificate} " + own_key, 8984, "UpdateActionResult", action_result={"exit_code": 7}), "Unauthenticated")
          refused(action_cache(client, "-plaintext", 8980, "GetActionResult"), "NotFound")
          status, output = action_cache(builder, "-cacert ${storeCertificate} " + own_key, 8984, "UpdateActionResult", action_result={"exit_code": 7})
          assert status == 0, f"a listed worker's key did not write:\n{output}"
          status, output = action_cache(client, "-plaintext", 8980, "GetActionResult")
          assert status == 0 and json.loads(output)["exitCode"] == 7, f"the worker's result is not what a client reads:\n{output}"

      with subtest("only a listed key registers a worker"):
          refused(register(client, "-cacert ${storeCertificate}"), "Unauthenticated")
          refused(register(client, "-plaintext"), "Failed to dial", "Unavailable")
          refused(register(rogue, "-cacert ${storeCertificate} " + own_key), "Unauthenticated")
          status, output = register(builder, "-cacert ${storeCertificate} " + own_key)
          assert status == 0, f"a listed worker's key did not register:\n{output}"

      with subtest("a result the other host's worker wrote is a hit for a client"):
          store.succeed(workers.format("stop"))
          produce = "cat /proc/sys/kernel/hostname > out; od -An -N16 -tx1 /dev/urandom >> out"
          status, output = run(client, produce, "--output-path=out", "--d=/root/first")
          assert status == 0, f"the action did not run on the builder:\n{output}"
          first = client.succeed("cat /root/first/out")
          assert first.splitlines()[0] == "builder", f"not the builder's result:\n{first}"
          builder.succeed(workers.format("stop"))
          for machine in [client, store]:
              status, output = run(machine, produce, "--output-path=out", "--d=/root/second", limit=30)
              assert status == 0, f"no hit on {machine.name} with every listed worker stopped:\n{output}"
              assert machine.succeed("cat /root/second/out") == first, f"{machine.name} read another result"

      with subtest("a worker with a key the store does not list runs nothing"):
          print(rogue.succeed("systemctl show -P ActiveState -P NRestarts buildbarn-worker; journalctl --no-pager -u buildbarn-worker | tail -n 4"))
          rogue.succeed("journalctl --no-pager -u buildbarn-worker | grep -F Unauthenticated")
          status, output = run(client, "echo ran on a worker the store does not list", uncached, limit=30)
          assert status != 0, f"an action ran with only the unlisted worker up:\n{output}"
          rogue.succeed("${as "buildbarn"} cat ${key} > /dev/null")
          print(rogue.fail("${as "buildbarn-run"} cat ${key} 2>&1"))
          print(rogue.fail("${as "agent"} cat ${key} 2>&1"))

      probe = (
          "for target in " + address + " 127.0.0.1; do for port in ${toString ports}; do"
          " if (exec 3<>/dev/tcp/$target/$port) 2>/dev/null; then echo $target:$port open; else echo $target:$port closed; fi;"
          " done; done > reach;"
          " for socket in ${toString sockets}; do"
          " if ${connect "$socket"} 2>/dev/null; then echo $socket open; else echo $socket closed; fi;"
          " done >> reach;"
          " if cat ${key} > /dev/null 2>&1; then echo key open; else echo key closed; fi >> reach;"
          " cat /proc/sys/kernel/hostname >> reach"
      )
      with subtest("an action reaches no listener, no inner socket and no key, on the store host and on another"):
          for machine in [store, builder]:
              machine.succeed(workers.format("start"))
              status, output = run(client, probe, uncached, "--output-path=reach", f"--d=/root/reach-{machine.name}")
              assert status == 0, f"the probing action did not run on {machine.name}:\n{output}"
              reach = client.succeed(f"cat /root/reach-{machine.name}/reach").splitlines()
              print(f"what an action on {machine.name} reaches:\n" + "\n".join(reach))
              assert reach[-1] == machine.name, f"the probe ran on {reach[-1]}"
              assert len(reach) == ${toString (2 * builtins.length ports + builtins.length sockets + 2)}
              assert all(line.endswith(" closed") for line in reach[:-1]), reach
              machine.succeed(workers.format("stop"))
          for port in ${builtins.toJSON ports}:
              store.succeed(f"(exec 3<>/dev/tcp/{address}/{port})")
              client.succeed(f"(exec 3<>/dev/tcp/{address}/{port})")

      with subtest("a new store generation empties the action cache before the store starts, and a failed emptying keeps the store down"):
          for machine in [store, client]:
              assert machine.succeed("cat ${generationFile}") == "1\n"
              machine.succeed(
                  "test \"$(stat -c '%a %U %G' ${generationFile})\" = '444 root root'",
                  "test \"$(stat -c '%a %U %G' /etc/buildbarn)\" = '755 root root'",
              )
          for user in ["buildbarn-run", "buildbarn", "agent"]:
              for attempt in ["echo 9 > ${generationFile}", "mv ${generationFile} /etc/buildbarn/moved", "touch /etc/buildbarn/added"]:
                  print(store.fail(f"${setpriv} --reuid={user} --regid={user} --init-groups sh -c {shlex.quote(attempt)} 2>&1"))
          for dependency in ["After", "Requires"]:
              store.succeed(
                  f"systemctl show -P {dependency} buildbarn-storage.service | tr ' ' '\n' | grep -qx ${emptying}.service"
              )
          assert emptied() == ["store generation none -> 1: removed 0 files under ${actionCache}"], emptied()

          store.succeed("systemctl restart ${emptying}")
          status, output = read_result()
          assert status == 0 and json.loads(output)["exitCode"] == 7, f"a restart under the same generation lost the result:\n{output}"
          assert emptied()[-1] == "store generation 1 is the recorded one: removed nothing under ${actionCache}", emptied()

          store.succeed("${pkgs.e2fsprogs}/bin/chattr +i ${actionCache}/blocks")
          print(store.execute("/run/current-system/specialisation/generation2/bin/switch-to-configuration test 2>&1")[1])
          store.succeed("systemctl is-failed ${emptying}")
          store.fail("systemctl is-active buildbarn-storage")
          store.fail("${as "buildbarn"} ${connect (builtins.head sockets)}")
          status, output = action_cache(client, "-plaintext", 8980, "GetActionResult")
          assert status != 0 and "exitCode" not in output, f"the store answered after a failed emptying:\n{output}"

          store.succeed("${pkgs.e2fsprogs}/bin/chattr -i ${actionCache}/blocks", "systemctl start buildbarn-storage")
          refused(read_result(), "NotFound")
          print(emptied())
          assert emptied()[-1].startswith("store generation 1 -> 2: removed ") and "removed 0 " not in emptied()[-1], emptied()
          assert store.succeed("cat ${generationFile} ${generationRecord}") == "2\n2\n"
          store.succeed("test -s /var/lib/buildbarn/storage/cas/blocks")

      with subtest("observation, asserted by north#1115 box 7b-runner-isolation: one action rewriting another's input"):
          builder.succeed(workers.format("start"))
          client.succeed("printf 'honest\\n' > /root/work/victim")
          meddle = (
              "end=$((SECONDS + 25)); while [ $SECONDS -lt $end ]; do"
              " for f in $(find ${buildDirectory} -name victim 2>/dev/null); do rm -f $f; echo forged > $f; done;"
              " sleep 0.2; done"
          )
          client.succeed(
              f"cd /root/work && ({trexe} {uncached} --input-path=input -- sh -c {shlex.quote(meddle)} > /root/meddle.log 2>&1 &)"
          )
          status, output = client.execute(
              f"cd /root/work && timeout 120 {trexe} {uncached} --input-path=victim --output-path=read --d=/root/victim"
              " -- sh -c 'sleep 8; cat victim > read' 2>&1"
          )
          read = client.execute("cat /root/victim/read")[1].strip()
          print(f"observation: with another action meddling, the victim action exited {status} and read: {read}")
    '';
}
