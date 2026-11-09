{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.sops-keyservice;
  username = config.myConfig.modules.users.username;
  agentKey = "/var/lib/sops-keyservice-agent/key.txt";
  instances = {
    sops-keyservice = {
      user = username;
      key = "/var/lib/sops-nix/key.txt";
      holds = "the admin age key";
    };
  }
  // lib.optionalAttrs (cfg.agentUser != null) {
    sops-keyservice-agent = {
      user = cfg.agentUser;
      key = agentKey;
      holds = "this host's agent age key";
    };
  };
  connection =
    service:
    pkgs.writeShellApplication {
      name = "${service}-connection";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.socat
      ];
      text = ''
        uid=''${1##*-}
        pid=''${1%-*}
        pid=''${pid##*-}
        pid=''${pid%%_*}
        parent=$(cut -d' ' -f4 "/proc/$pid/stat" 2>/dev/null || echo 0)
        line() { tr '\0' ' ' <"/proc/$1/cmdline" 2>/dev/null | cut -c1-240 || true; }
        printf 'sops key request: uid %s pid %s (%s) parent %s (%s) cgroup %s\n' "$uid" "$pid" "$(line "$pid")" "$parent" "$(line "$parent")" "$(cut -d: -f3 "/proc/$pid/cgroup" 2>/dev/null || true)" >&2
        for _ in $(seq 50); do [ -S /run/${service}/backend.sock ] && break; sleep 0.1; done
        exec socat STDIO UNIX-CONNECT:/run/${service}/backend.sock
      '';
    };
  client = pkgs.writeShellScriptBin "sops" ''
    socket=/run/sops-keyservice.sock
    ${lib.optionalString (cfg.agentUser != null) ''
      [ "$(${pkgs.coreutils}/bin/id -un)" = ${lib.escapeShellArg cfg.agentUser} ] && socket=/run/sops-keyservice-agent.sock
    ''}
    SOPS_KEYSERVICE=unix://$socket SOPS_ENABLE_LOCAL_KEYSERVICE=false exec ${pkgs.sops}/bin/sops "$@"
  '';
  confined = service: {
    User = service;
    Group = service;
    NoNewPrivileges = true;
    CapabilityBoundingSet = "";
    PrivateNetwork = true;
    PrivateTmp = true;
    PrivateDevices = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectKernelLogs = true;
    ProtectControlGroups = true;
    ProtectClock = true;
    ProtectHostname = true;
    RestrictAddressFamilies = "AF_UNIX";
    RestrictNamespaces = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    LockPersonality = true;
    SystemCallArchitectures = "native";
    SystemCallFilter = "@system-service";
  };
  units = service: instance: {
    services = {
      ${service} = {
        description = "sops key service holding ${instance.holds}";
        wantedBy = [ "multi-user.target" ];
        environment.SOPS_AGE_KEY_FILE = "%d/age-key";
        serviceConfig = confined service // {
          ExecStart = "${pkgs.sops}/bin/sops keyservice --network unix --address /run/${service}/backend.sock --verbose";
          LoadCredential = "age-key:${instance.key}";
          RuntimeDirectory = service;
          RuntimeDirectoryMode = "0700";
          Restart = "on-failure";
          MemoryDenyWriteExecute = true;
        };
      };
      "${service}-request@" = {
        description = "Log one sops key request and relay it to ${service}";
        requires = [ "${service}.service" ];
        after = [ "${service}.service" ];
        serviceConfig = confined service // {
          ExecStart = "${connection service}/bin/${service}-connection %i";
          StandardInput = "socket";
          StandardOutput = "socket";
          StandardError = "journal";
        };
      };
    };
    sockets."${service}-request" = {
      description = "sops key requests from ${instance.user}";
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = "/run/${service}.sock";
        Accept = true;
        SocketUser = instance.user;
        SocketMode = "0600";
      };
    };
  };
in
{
  options.myConfig.modules.sops-keyservice = {
    enable = lib.mkEnableOption "sops decryption for the login user through a logged key service, while the admin age key at /var/lib/sops-nix/key.txt stays readable by root alone";
    agentUser = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "User the fleet's agents run as. When set, a second key service, sops-keyservice-agent, holds an age key generated on this host at ${agentKey} (readable by root alone, public half in the journal of sops-keyservice-agent-key.service) and serves only this user, so the agent decrypts exactly the files whose recipients name that key.";
    };
  };
  config = lib.mkIf cfg.enable {
    users = {
      users = lib.mapAttrs (service: _: {
        isSystemUser = true;
        group = service;
      }) instances;
      groups = lib.mapAttrs (_: _: { }) instances;
    };
    environment.systemPackages = [ (lib.hiPrio client) ];
    systemd = lib.mkMerge (
      [
        { tmpfiles.rules = [ "z /var/lib/sops-nix/key.txt 0400 root root -" ]; }
        (lib.mkIf (cfg.agentUser != null) {
          services.sops-keyservice-agent-key = {
            description = "Generate this host's agent age key once, readable by root alone";
            requiredBy = [ "sops-keyservice-agent.service" ];
            before = [ "sops-keyservice-agent.service" ];
            unitConfig.ConditionPathExists = "!${agentKey}";
            serviceConfig = {
              Type = "oneshot";
              UMask = "0077";
              StateDirectory = "sops-keyservice-agent";
              StateDirectoryMode = "0700";
              ExecStart = "${pkgs.age}/bin/age-keygen -o ${agentKey}";
            };
          };
        })
      ]
      ++ lib.mapAttrsToList units instances
    );
  };
}
