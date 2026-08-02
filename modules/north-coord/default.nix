{ config, lib, pkgs, inputs, ... }:

let
  username = config.myConfig.modules.users.username;
  homeDir = config.myConfig.modules.users.homeDir;
  framPkg = inputs.fram.packages."${pkgs.stdenv.hostPlatform.system}".default;
  framRev = inputs.fram.rev;
  northPkg = inputs.north.packages."${pkgs.stdenv.hostPlatform.system}".default;
  northCoordSdListenChecked = pkgs.runCommand "north-coord-sd-listen-checked" { } ''
    wrapper=${northPkg}/bin/north-coord-sd-listen
    if [ ! -x "$wrapper" ]; then
      echo "north-coord socketActivation requires executable $wrapper" >&2
      exit 1
    fi
    mkdir -p "$out/bin"
    ln -s "$wrapper" "$out/bin/north-coord-sd-listen"
  '';
  runtimeState = "${homeDir}/.local/state/north/fram-runtime";
  telemetryRuntimeState = "${homeDir}/.local/state/north/fram-telemetry-runtime";
  stageA = config.myConfig.modules.north-coord.stageATelemetryPartition;
  pairTarget = "north-coord-pair.target";
  pairPrepareUnit = "north-coord-pair-prepare.service";
  mkNorthCoordRuntime = name: state: primaryLog: peerLog: port: unit: transactionOwner: pkgs.writeShellApplication {
    name = name;
    runtimeInputs = with pkgs; [ bash coreutils git iproute2 systemd util-linux ];
    text = ''
      export NORTH_COORD_RUNTIME_STATE=${state}
      export NORTH_COORD_FRAM_PACKAGE=${framPkg}
      export NORTH_COORD_FRAM_PACKAGE_REV=${framRev}
      export NORTH_COORD_FRAM_JAVA=${pkgs.jdk}/bin/java
      export NORTH_COORD_FRAM_CHECKOUT=${homeDir}/code/fram/main
      export NORTH_COORD_NORTH_PACKAGE=${northPkg}
      export NORTH_COORD_FRAM_LOG=${primaryLog}
      export NORTH_COORD_TELEMETRY_LOG=${peerLog}
      export NORTH_COORD_SYSTEMD_UNIT=${unit}
      export NORTH_COORD_FRAM_PORT=${port}
      export NORTH_COORD_TELEMETRY_PORT=7978
      export NORTH_COORD_SINGLE_ORIGIN=${if stageA then "1" else "0"}
      export NORTH_COORD_TRANSACTION_OWNER=${transactionOwner}
      export NORTH_COORD_CORPUS_SYSTEMD_UNIT=${if stageA then pairTarget else unit}
      export NORTH_COORD_RESTART_SYSTEMD_UNIT=${if stageA then pairTarget else unit}
      export NORTH_COORD_RESTART_PREPARE_SYSTEMD_UNIT=${if stageA then pairPrepareUnit else ""}
      ${builtins.readFile ./north-coord-runtime}
    '';
  };
  northCoordRuntime = mkNorthCoordRuntime "north-coord-runtime" runtimeState "${homeDir}/.local/state/north/coordination.log" "${homeDir}/.local/state/north/telemetry.log" "7977" "north-coord.service" "1";
  northTelemetryCoordRuntime = mkNorthCoordRuntime "north-telemetry-coord-runtime" telemetryRuntimeState "${homeDir}/.local/state/north/telemetry.log" "${homeDir}/.local/state/north/coordination.log" "7978" "north-telemetry-coord.service" "0";
  coordHeapOptions = "-XX:+UseG1GC -Xmx16g";
  telemetryHeapOptions = "-XX:+UseG1GC -Xmx8g";
  coordMemoryHigh = "18G";
  telemetryMemoryHigh = "10G";
  coordMemoryMax = "20G";
  telemetryMemoryMax = "12G";
  coordCpuQuota = "400%";
  telemetryCpuQuota = "200%";
  serviceTasksMax = 128;
  serviceRestart = "on-failure";
  connectionWorkers = "32";
  connectionQueue = "128";
  requestTimeoutMs = "30000";
  serviceEnvironment = {
    HOME = homeDir;
    FRAM_REQUIRE_LOG_FENCE = "1";
    FRAM_QUERY_TIMEOUT_MS = "30000";
    FRAM_CONNECTION_WORKERS = connectionWorkers;
    FRAM_CONNECTION_QUEUE = connectionQueue;
    FRAM_REQUEST_TIMEOUT_MS = requestTimeoutMs;
    FRAM_TELEMETRY_LOG = "${homeDir}/.local/state/north/telemetry.log";
  };
  serviceConfigBase = {
    Type = "simple";
    User = username;
    WorkingDirectory = homeDir;
    Restart = serviceRestart;
    RestartSec = 2;
    TimeoutStopSec = "15s";
    SendSIGKILL = true;
    MemorySwapMax = "0";
  };
in
{
  options.myConfig.modules.north-coord.enable = lib.mkEnableOption "Personal North coordinator daemon (:7977) — sole-writer fact-graph service for Tom's canonical log";
  options.myConfig.modules.north-coord.socketActivation = lib.mkEnableOption "systemd socket activation for :7977 (requires the Fram fd-consumer and north-coord-sd-listen)";
  options.myConfig.modules.north-coord.stageATelemetryPartition = lib.mkEnableOption "independent single-origin coordination (:7977) and telemetry (:7978) writers; option-off is the no-data-migration rollback";
  config = lib.mkIf config.myConfig.modules.north-coord.enable {
    assertions = [
      {
        assertion = ((!stageA) || config.myConfig.modules.north-coord.socketActivation);
        message = "north-coord.stageATelemetryPartition requires socketActivation so both writer ports remain systemd-owned";
      }
    ];
    environment.systemPackages = ([ northCoordRuntime ] ++ (lib.optional stageA northTelemetryCoordRuntime));
    environment.variables = lib.mkIf stageA {
      NORTH_TELEMETRY_PARTITION = "1";
      NORTH_TELEMETRY_PORT = "7978";
    };
    home-manager.users.${username} = ({ config, ... }: {
      home.sessionVariables = lib.mkIf stageA {
        NORTH_TELEMETRY_PARTITION = "1";
        NORTH_TELEMETRY_PORT = "7978";
      };
    });
    systemd.sockets.north-coord = lib.mkIf config.myConfig.modules.north-coord.socketActivation {
      description = "North coordinator activation socket (:7977)";
      wantedBy = [ "sockets.target" ];
      listenStreams = [ "127.0.0.1:7977" ];
      socketConfig = {
        TriggerLimitIntervalSec = 0;
        Backlog = 512;
        FileDescriptorName = "north-coord";
      };
    };
    systemd.sockets.north-telemetry-coord = lib.mkIf stageA {
      description = "North telemetry coordinator activation socket (:7978)";
      wantedBy = [ "sockets.target" ];
      listenStreams = [ "127.0.0.1:7978" ];
      socketConfig = {
        TriggerLimitIntervalSec = 0;
        Backlog = 512;
        FileDescriptorName = "north-coord";
      };
    };
    systemd.targets.north-coord-pair = lib.mkIf stageA {
      description = "North Stage-A coordination + telemetry writer pair";
      wantedBy = [ "multi-user.target" ];
      requires = [ "north-coord-pair-prepare.service" ];
      after = [ "north-coord-pair-prepare.service" ];
      wants = [
        "north-coord.socket"
        "north-telemetry-coord.socket"
        "north-coord.service"
        "north-telemetry-coord.service"
        "north-coord-pair-settle.service"
      ];
    };
    systemd.services.north-coord-pair-prepare = lib.mkIf stageA {
      description = "Prepare both North Stage-A writer runtimes";
      restartIfChanged = false;
      stopIfChanged = false;
      before = [ "north-coord.service" "north-telemetry-coord.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = username;
        WorkingDirectory = homeDir;
        RemainAfterExit = true;
        ExecStartPre = [
          "${northCoordRuntime}/bin/north-coord-runtime ensure-default"
          "${northTelemetryCoordRuntime}/bin/north-telemetry-coord-runtime ensure-default"
        ];
        ExecStart = "${northCoordRuntime}/bin/north-coord-runtime prepare";
      };
    };
    systemd.services.north-coord-pair-settle = lib.mkIf stageA {
      description = "Settle the North Stage-A pair after both writers start";
      restartIfChanged = false;
      stopIfChanged = false;
      requires = [ "north-coord.service" "north-telemetry-coord.service" ];
      after = [ "north-coord.service" "north-telemetry-coord.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = username;
        WorkingDirectory = homeDir;
        ExecStart = "${northCoordRuntime}/bin/north-coord-runtime settle";
      };
    };
    systemd.services.north-coord = {
      description = "North coordinator — personal fact-graph daemon (:7977)";
      wantedBy = if stageA then [ ] else [ "multi-user.target" ];
      partOf = lib.optional stageA pairTarget;
      requires = (lib.optional config.myConfig.modules.north-coord.socketActivation "north-coord.socket" ++ lib.optional stageA "north-coord-pair-prepare.service");
      after = ([ "network.target" ] ++ lib.optional config.myConfig.modules.north-coord.socketActivation "north-coord.socket" ++ lib.optional stageA "north-coord-pair-prepare.service");
      path = with pkgs; [ clojure jdk bash coreutils git ];
      startLimitIntervalSec = 0;
      restartIfChanged = false;
      stopIfChanged = false;
      environment = (serviceEnvironment // {
        JDK_JAVA_OPTIONS = coordHeapOptions;
      });
      serviceConfig = (serviceConfigBase // {
        MemoryHigh = coordMemoryHigh;
        MemoryMax = coordMemoryMax;
        CPUQuota = coordCpuQuota;
        TasksMax = serviceTasksMax;
        Sockets = lib.mkIf config.myConfig.modules.north-coord.socketActivation "north-coord.socket";
        ExecStartPre = if stageA then [ ] else [
          "${northCoordRuntime}/bin/north-coord-runtime ensure-default"
          "${northCoordRuntime}/bin/north-coord-runtime prepare"
        ];
        ExecStart = if config.myConfig.modules.north-coord.socketActivation then "${northCoordSdListenChecked}/bin/north-coord-sd-listen ${northCoordRuntime}/bin/north-coord-runtime start" else "${northCoordRuntime}/bin/north-coord-runtime start";
        ExecStartPost = lib.mkIf (!stageA) "${northCoordRuntime}/bin/north-coord-runtime settle";
      });
    };
    systemd.services.north-telemetry-coord = lib.mkIf stageA {
      description = "North telemetry coordinator — sole writer (:7978)";
      partOf = [ pairTarget ];
      requires = [ "north-telemetry-coord.socket" "north-coord-pair-prepare.service" ];
      after = [
        "network.target"
        "north-telemetry-coord.socket"
        "north-coord-pair-prepare.service"
      ];
      path = with pkgs; [ clojure jdk bash coreutils git ];
      startLimitIntervalSec = 0;
      restartIfChanged = false;
      stopIfChanged = false;
      environment = (serviceEnvironment // {
        FRAM_TELEMETRY_LOG = "${homeDir}/.local/state/north/coordination.log";
        JDK_JAVA_OPTIONS = telemetryHeapOptions;
      });
      serviceConfig = (serviceConfigBase // {
        MemoryHigh = telemetryMemoryHigh;
        MemoryMax = telemetryMemoryMax;
        CPUQuota = telemetryCpuQuota;
        TasksMax = serviceTasksMax;
        Sockets = "north-telemetry-coord.socket";
        ExecStart = "${northCoordSdListenChecked}/bin/north-coord-sd-listen ${northTelemetryCoordRuntime}/bin/north-telemetry-coord-runtime start";
      });
    };
  };
}
