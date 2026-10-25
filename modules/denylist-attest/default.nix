{
  config,
  lib,
  pkgs,
  jobRun,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.denylist-attest;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  south = "${homeDir}/code/south";
  gh =
    if config.myConfig.modules.github-pat.enable then
      config.myConfig.modules.github-pat.gh
    else
      pkgs.gh;
in
{
  options.myConfig.modules.denylist-attest.enable =
    lib.mkEnableOption "denylist-attest: every five minutes, scan new claude/ branch tips of the public Autoland repositories against the private deny-list and post their denylist commit status; enable it on exactly one host, one with the south checkout and a GitHub token that may write commit statuses and dispatch workflows";
  config = lib.mkIf cfg.enable {
    systemd = {
      services.denylist-attest = {
        description = "Attest claude/ branch tips against the private deny-list";
        unitConfig.ConditionPathIsExecutable = "${northBin}/north";
        path = [
          gh
          pkgs.git
          pkgs.gitleaks
          pkgs.coreutils
          "/run/current-system/sw"
        ];
        environment = {
          XDG_CACHE_HOME = "/var/cache/denylist-attest";
          GH_NO_UPDATE_NOTIFIER = "1";
        };
        serviceConfig = {
          Type = "oneshot";
          User = username;
          CacheDirectory = "denylist-attest";
          TimeoutStartSec = "4min";
          ExecStart = jobRun "denylist-attest" "${northBin}/north denylist attest --south ${south} --repo tompassarelli/smashcraft --repo tompassarelli/wisp";
          CapabilityBoundingSet = "";
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = "read-only";
          ReadWritePaths = [
            "${south}/main/.git"
            "-${homeDir}/.local/state/threads"
          ];
          PrivateTmp = true;
          PrivateDevices = true;
          PrivateUsers = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          ProtectClock = true;
          ProtectHostname = true;
          ProtectProc = "invisible";
          ProcSubset = "pid";
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          RestrictNamespaces = true;
          SystemCallArchitectures = "native";
          SystemCallFilter = [
            "@system-service"
            "~@privileged @resources"
          ];
          RestrictAddressFamilies = [
            "AF_UNIX"
            "AF_INET"
            "AF_INET6"
          ];
          UMask = "0077";
        };
      };
      timers.denylist-attest = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* *:00/5:00";
          Persistent = true;
        };
      };
    };
  };
}
