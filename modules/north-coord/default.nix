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
      export NORTH_COORD_FRAM_CHECKOUT=${homeDir}/code/fram
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
  coordinationLog = "${homeDir}/.local/state/north/coordination.log";
  telemetryLog = "${homeDir}/.local/state/north/telemetry.log";
  cutoverState = "/var/lib/north-coord-cutover";
  cutoverToken = "${cutoverState}/cutover.token";
  selectorMap = "${cutoverState}/route.map";
  selectorTransaction = "${cutoverState}/selector.transaction";
  selectorLock = "${cutoverState}/selector.lock";
  bootstrapMarker = "${cutoverState}/bootstrap-complete";
  proxyRuntime = "/run/north-coord-proxy";
  proxyAdminSocket = "${proxyRuntime}/admin.sock";
  proxyFrontend = "north-public";
  blueCoordPort = "17977";
  blueTelemetryPort = "17978";
  greenCoordPort = "27977";
  greenTelemetryPort = "27978";
  blueCoordRuntime = mkNorthCoordRuntime "north-coord-blue-runtime" "${runtimeState}-blue" coordinationLog telemetryLog blueCoordPort "north-coord-blue.service" "1";
  blueTelemetryRuntime = mkNorthCoordRuntime "north-telemetry-coord-blue-runtime" "${telemetryRuntimeState}-blue" telemetryLog coordinationLog blueTelemetryPort "north-telemetry-coord-blue.service" "0";
  greenCoordRuntime = mkNorthCoordRuntime "north-coord-green-runtime" "${runtimeState}-green" coordinationLog telemetryLog greenCoordPort "north-coord-green.service" "1";
  greenTelemetryRuntime = mkNorthCoordRuntime "north-telemetry-coord-green-runtime" "${telemetryRuntimeState}-green" telemetryLog coordinationLog greenTelemetryPort "north-telemetry-coord-green.service" "0";
  framCutoverChecked = pkgs.runCommand "fram-cutover-checked" { } ''
    cutover=${framPkg}/bin/fram-cutover
    if [ ! -x "$cutover" ]; then
      echo "pinned Fram lacks fram-cutover" >&2
      exit 1
    fi
    mkdir -p "$out/bin"
    cp "$cutover" "$out/bin/fram-cutover"
  '';
  slotStart = pkgs.writeShellApplication {
    name = "north-coord-slot-start";
    runtimeInputs = with pkgs; [ bash coreutils ];
    text = builtins.readFile ./north-coord-slot-start;
  };
  cutoverGate = pkgs.writeShellApplication {
    name = "north-coord-cutover-gate";
    runtimeInputs = with pkgs; [ babashka bash coreutils ];
    text = ''
      export NORTH_COORD_CUTOVER_BIN=${framCutoverChecked}/bin/fram-cutover
      export NORTH_COORD_CUTOVER_TOKEN_FILE=${cutoverToken}
      export NORTH_COORD_CUTOVER_STATE=${cutoverState}
      export NORTH_COORD_COORD_LOG=${coordinationLog}
      export NORTH_COORD_TELEMETRY_LOG=${telemetryLog}
      export NORTH_COORD_BLUE_COORD_PORT=${blueCoordPort}
      export NORTH_COORD_BLUE_TELEMETRY_PORT=${blueTelemetryPort}
      export NORTH_COORD_GREEN_COORD_PORT=${greenCoordPort}
      export NORTH_COORD_GREEN_TELEMETRY_PORT=${greenTelemetryPort}
      ${builtins.readFile ./north-coord-cutover-gate}
    '';
  };
  selectorPromote = pkgs.writeShellApplication {
    name = "north-coord-selector-promote";
    runtimeInputs = [ cutoverGate ];
    text = ''
      exec ${cutoverGate}/bin/north-coord-cutover-gate promote "$@"
    '';
  };
  selectorRollback = pkgs.writeShellApplication {
    name = "north-coord-selector-rollback";
    runtimeInputs = [ cutoverGate ];
    text = ''
      exec ${cutoverGate}/bin/north-coord-cutover-gate rollback "$@"
    '';
  };
  selectorVerify = pkgs.writeShellApplication {
    name = "north-coord-selector-verify";
    runtimeInputs = [ cutoverGate ];
    text = ''
      exec ${cutoverGate}/bin/north-coord-cutover-gate verify "$@"
    '';
  };
  selector = pkgs.writeShellApplication {
    name = "north-coord-selector";
    runtimeInputs = with pkgs; [ bash coreutils socat util-linux ];
    text = ''
      export NORTH_COORD_SELECTOR_SOCKET=${proxyAdminSocket}
      export NORTH_COORD_SELECTOR_MAP=${selectorMap}
      export NORTH_COORD_SELECTOR_FRONTEND=${proxyFrontend}
      export NORTH_COORD_SELECTOR_LOCK=${selectorLock}
      export NORTH_COORD_SELECTOR_TRANSACTION=${selectorTransaction}
      export NORTH_COORD_SELECTOR_PROMOTE_COMMAND=${selectorPromote}/bin/north-coord-selector-promote
      export NORTH_COORD_SELECTOR_ROLLBACK_COMMAND=${selectorRollback}/bin/north-coord-selector-rollback
      export NORTH_COORD_SELECTOR_VERIFY_COMMAND=${selectorVerify}/bin/north-coord-selector-verify
      export NORTH_COORD_SELECTOR_DRAIN_TIMEOUT=15
      ${builtins.readFile ./north-coord-selector}
    '';
  };
  proxyConfig = pkgs.writeText "north-coord-haproxy.cfg" ''
    global
      stats socket ${proxyAdminSocket} mode 600 level admin
      maxconn 4096

    defaults
      mode tcp
      timeout connect 2s
      timeout client 30s
      timeout server 30s

    frontend ${proxyFrontend}
      bind fd@3
      bind fd@4
      acl is_coord dst_port 7977
      acl route_blue str(active),map(${selectorMap}) -m str blue
      use_backend coord-blue if is_coord route_blue
      use_backend coord-green if is_coord !route_blue
      use_backend telemetry-blue if !is_coord route_blue
      default_backend telemetry-green

    backend coord-blue
      server only 127.0.0.1:${blueCoordPort}
    backend coord-green
      server only 127.0.0.1:${greenCoordPort}
    backend telemetry-blue
      server only 127.0.0.1:${blueTelemetryPort}
    backend telemetry-green
      server only 127.0.0.1:${greenTelemetryPort}
  '';
  proxyStart = pkgs.writeShellApplication {
    name = "north-coord-proxy-start";
    runtimeInputs = with pkgs; [ bash coreutils haproxy ];
    text = ''
      export NORTH_COORD_HAPROXY=${pkgs.haproxy}/bin/haproxy
      export NORTH_COORD_HAPROXY_CONFIG=${proxyConfig}
      ${builtins.readFile ./north-coord-proxy-start}
    '';
  };
  bootstrap = pkgs.writeShellApplication {
    name = "north-coord-bootstrap";
    runtimeInputs = with pkgs; [ bash coreutils procps systemd ];
    text = ''
      export NORTH_COORD_CUTOVER_USER=${username}
      export NORTH_COORD_CUTOVER_GROUP=users
      export NORTH_COORD_CUTOVER_STATE=${cutoverState}
      export NORTH_COORD_CUTOVER_TOKEN_FILE=${cutoverToken}
      export NORTH_COORD_SELECTOR_MAP=${selectorMap}
      export NORTH_COORD_BOOTSTRAP_MARKER=${bootstrapMarker}
      export NORTH_COORD_CUTOVER_GATE=${cutoverGate}/bin/north-coord-cutover-gate
      export NORTH_COORD_SELECTOR=${selector}/bin/north-coord-selector
      export NORTH_COORD_COORD_LOG=${coordinationLog}
      export NORTH_COORD_TELEMETRY_LOG=${telemetryLog}
      ${builtins.readFile ./north-coord-bootstrap}
    '';
  };
  serviceEnvironment = {
    HOME = homeDir;
    FRAM_REQUIRE_LOG_FENCE = "1";
    FRAM_QUERY_TIMEOUT_MS = "30000";
    FRAM_TELEMETRY_LOG = "${homeDir}/.local/state/north/telemetry.log";
    JDK_JAVA_OPTIONS = "-Xmx6g";
  };
  serviceConfigBase = {
    Type = "simple";
    User = username;
    WorkingDirectory = homeDir;
    Restart = "always";
    RestartSec = 2;
    TimeoutStopSec = "15s";
    SendSIGKILL = true;
    MemorySwapMax = "0";
  };
  mkSlotService = description: slot: runtimeCommand: peerLog: heapMax: memoryMax: {
    description = description;
    restartIfChanged = false;
    stopIfChanged = false;
    after = [ "network.target" ];
    path = with pkgs; [ clojure jdk bash coreutils git ];
    startLimitIntervalSec = 0;
    unitConfig = {
      ConditionPathExists = cutoverToken;
    };
    environment = (serviceEnvironment // {
      FRAM_TELEMETRY_LOG = peerLog;
      JDK_JAVA_OPTIONS = heapMax;
      NORTH_COORD_SLOT = slot;
      NORTH_COORD_SELECTOR_MAP = selectorMap;
      NORTH_COORD_CUTOVER_TOKEN_FILE = cutoverToken;
      NORTH_COORD_SLOT_RUNTIME = runtimeCommand;
    });
    serviceConfig = (serviceConfigBase // {
      MemoryMax = memoryMax;
      ExecStartPre = [ "${runtimeCommand} ensure-default" ];
      ExecStart = "${slotStart}/bin/north-coord-slot-start";
    });
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
    environment.systemPackages = ([ northCoordRuntime ] ++ (lib.optional stageA northTelemetryCoordRuntime) ++ (if stageA then [ selector cutoverGate bootstrap ] else [ ]));
    environment.variables = lib.mkIf stageA {
      NORTH_TELEMETRY_PARTITION = "1";
      NORTH_TELEMETRY_PORT = "7978";
      FRAM_TELEMETRY_LOG = "${homeDir}/.local/state/north/telemetry.log";
    };
    home-manager.users.${username} = ({ config, ... }: {
      home.sessionVariables = lib.mkIf stageA {
        NORTH_TELEMETRY_PARTITION = "1";
        NORTH_TELEMETRY_PORT = "7978";
        FRAM_TELEMETRY_LOG = "${homeDir}/.local/state/north/telemetry.log";
      };
    });
    systemd.sockets.north-coord = lib.mkIf config.myConfig.modules.north-coord.socketActivation {
      description = "North coordinator activation socket (:7977)";
      wantedBy = [ "sockets.target" ];
      listenStreams = [ "127.0.0.1:7977" ];
      socketConfig = {
        Backlog = 4096;
        FileDescriptorName = "north-coord";
      };
    };
    systemd.sockets.north-telemetry-coord = lib.mkIf stageA {
      description = "North telemetry coordinator activation socket (:7978)";
      wantedBy = [ "sockets.target" ];
      listenStreams = [ "127.0.0.1:7978" ];
      socketConfig = {
        Backlog = 4096;
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
    systemd.targets.north-coord-blue-green = lib.mkIf stageA {
      description = "North durable blue/green coordinator pair";
      wantedBy = [ "multi-user.target" ];
      unitConfig = {
        ConditionPathExists = bootstrapMarker;
      };
      requires = [ "north-coord.socket" "north-telemetry-coord.socket" ];
      wants = [
        "north-coord-blue.service"
        "north-telemetry-coord-blue.service"
        "north-coord-green.service"
        "north-telemetry-coord-green.service"
        "north-coord-proxy.service"
      ];
      after = [
        "north-coord-blue.service"
        "north-telemetry-coord-blue.service"
        "north-coord-green.service"
        "north-telemetry-coord-green.service"
        "north-coord-proxy.service"
      ];
    };
    systemd.services.north-coord-pair-prepare = lib.mkIf stageA {
      description = "Prepare both North Stage-A writer runtimes";
      unitConfig = {
        ConditionPathExists = "!${bootstrapMarker}";
      };
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
      unitConfig = {
        ConditionPathExists = "!${bootstrapMarker}";
      };
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
      unitConfig = lib.mkIf stageA {
        ConditionPathExists = "!${bootstrapMarker}";
      };
      partOf = lib.optional stageA pairTarget;
      requires = (lib.optional config.myConfig.modules.north-coord.socketActivation "north-coord.socket" ++ lib.optional stageA "north-coord-pair-prepare.service");
      after = ([ "network.target" ] ++ lib.optional config.myConfig.modules.north-coord.socketActivation "north-coord.socket" ++ lib.optional stageA "north-coord-pair-prepare.service");
      path = with pkgs; [ clojure jdk bash coreutils git ];
      startLimitIntervalSec = 0;
      restartIfChanged = false;
      stopIfChanged = false;
      environment = (serviceEnvironment // {
        JDK_JAVA_OPTIONS = "-Xmx16g";
      });
      serviceConfig = (serviceConfigBase // {
        MemoryMax = "32G";
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
      unitConfig = {
        ConditionPathExists = "!${bootstrapMarker}";
      };
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
      });
      serviceConfig = (serviceConfigBase // {
        MemoryMax = "8G";
        Sockets = "north-telemetry-coord.socket";
        ExecStart = "${northCoordSdListenChecked}/bin/north-coord-sd-listen ${northTelemetryCoordRuntime}/bin/north-telemetry-coord-runtime start";
      });
    };
    systemd.services.north-coord-blue = lib.mkIf stageA (mkSlotService "North coordination private blue generation (:17977)" "blue" "${blueCoordRuntime}/bin/north-coord-blue-runtime" telemetryLog "-Xmx16g" "32G");
    systemd.services.north-telemetry-coord-blue = lib.mkIf stageA (mkSlotService "North telemetry private blue generation (:17978)" "blue" "${blueTelemetryRuntime}/bin/north-telemetry-coord-blue-runtime" coordinationLog "-Xmx6g" "8G");
    systemd.services.north-coord-green = lib.mkIf stageA (mkSlotService "North coordination private green generation (:27977)" "green" "${greenCoordRuntime}/bin/north-coord-green-runtime" telemetryLog "-Xmx16g" "32G");
    systemd.services.north-telemetry-coord-green = lib.mkIf stageA (mkSlotService "North telemetry private green generation (:27978)" "green" "${greenTelemetryRuntime}/bin/north-telemetry-coord-green-runtime" coordinationLog "-Xmx6g" "8G");
    systemd.services.north-coord-proxy = lib.mkIf stageA {
      description = "North permanent public selector for coordination + telemetry";
      requires = [ "north-coord.socket" "north-telemetry-coord.socket" ];
      wants = [
        "north-coord-blue.service"
        "north-telemetry-coord-blue.service"
        "north-coord-green.service"
        "north-telemetry-coord-green.service"
      ];
      after = [
        "north-coord.socket"
        "north-telemetry-coord.socket"
        "north-coord-blue.service"
        "north-telemetry-coord-blue.service"
        "north-coord-green.service"
        "north-telemetry-coord-green.service"
      ];
      restartIfChanged = false;
      stopIfChanged = false;
      unitConfig = {
        ConditionPathExists = bootstrapMarker;
      };
      environment = {
        NORTH_COORD_BOOTSTRAP_MARKER = bootstrapMarker;
      };
      path = with pkgs; [ bash coreutils haproxy socat util-linux ];
      serviceConfig = {
        Type = "simple";
        User = username;
        WorkingDirectory = homeDir;
        RuntimeDirectory = "north-coord-proxy";
        RuntimeDirectoryMode = "0700";
        Restart = "always";
        RestartSec = 1;
        TimeoutStopSec = "15s";
        SendSIGKILL = true;
        Sockets = [ "north-coord.socket" "north-telemetry-coord.socket" ];
        ExecStartPre = [ "${selector}/bin/north-coord-selector prestart" ];
        ExecStart = "${proxyStart}/bin/north-coord-proxy-start";
      };
    };
    systemd.services.north-coord-bootstrap = lib.mkIf stageA {
      description = "One-time bounded legacy-to-blue-green North migration";
      restartIfChanged = false;
      stopIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${bootstrap}/bin/north-coord-bootstrap";
      };
    };
  };
}
