{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.sops-keyservice;
  username = config.myConfig.modules.users.username;
  service = "sops-keyservice";
  backend = "/run/${service}/backend.sock";
  socket = "/run/${service}.sock";
  connection = pkgs.writeShellApplication {
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
      for _ in $(seq 50); do [ -S ${backend} ] && break; sleep 0.1; done
      exec socat STDIO UNIX-CONNECT:${backend}
    '';
  };
  client = pkgs.writeShellScriptBin "sops" ''
    SOPS_KEYSERVICE=unix://${socket} SOPS_ENABLE_LOCAL_KEYSERVICE=false exec ${pkgs.sops}/bin/sops "$@"
  '';
  confined = {
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
in
{
  options.myConfig.modules.sops-keyservice.enable =
    lib.mkEnableOption "sops decryption for the login user through a logged key service, while the admin age key at /var/lib/sops-nix/key.txt stays readable by root alone";
  config = lib.mkIf cfg.enable {
    users = {
      users.${service} = {
        isSystemUser = true;
        group = service;
      };
      groups.${service} = { };
    };
    environment.systemPackages = [ (lib.hiPrio client) ];
    systemd = {
      tmpfiles.rules = [ "z /var/lib/sops-nix/key.txt 0400 root root -" ];
      services = {
        ${service} = {
          description = "sops key service holding the admin age key";
          wantedBy = [ "multi-user.target" ];
          environment.SOPS_AGE_KEY_FILE = "%d/age-key";
          serviceConfig = confined // {
            ExecStart = "${pkgs.sops}/bin/sops keyservice --network unix --address ${backend} --verbose";
            LoadCredential = "age-key:/var/lib/sops-nix/key.txt";
            RuntimeDirectory = service;
            RuntimeDirectoryMode = "0700";
            Restart = "on-failure";
            MemoryDenyWriteExecute = true;
          };
        };
        "${service}-request@" = {
          description = "Log one sops key request and relay it to the key service";
          requires = [ "${service}.service" ];
          after = [ "${service}.service" ];
          serviceConfig = confined // {
            ExecStart = "${connection}/bin/${service}-connection %i";
            StandardInput = "socket";
            StandardOutput = "socket";
            StandardError = "journal";
          };
        };
      };
      sockets."${service}-request" = {
        description = "sops key requests from the login user";
        wantedBy = [ "sockets.target" ];
        socketConfig = {
          ListenStream = socket;
          Accept = true;
          SocketUser = username;
          SocketMode = "0600";
        };
      };
    };
  };
}
