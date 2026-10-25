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
  repos = [
    "smashcraft"
    "wisp"
  ];
  secret = name: config.sops.secrets."denylist-attest-${name}".path;
  request = builtins.toJSON {
    repositories = repos;
    permissions = {
      statuses = "write";
      actions = "write";
      contents = "read";
    };
  };
  mint = pkgs.writeShellApplication {
    name = "denylist-attest-mint";
    runtimeInputs = [
      pkgs.gh-token
      pkgs.curl
      pkgs.jq
      pkgs.coreutils
    ];
    text = ''
      jwt=$(gh-token generate --jwt --duration 2 --app-id "$(cat ${secret "app-id"})" --key ${secret "private-key"})
      printf 'header = "Authorization: Bearer %s"\n' "$jwt" \
        | curl -fsS --max-time 30 --config - -X POST -H 'Accept: application/vnd.github+json' \
          -d ${lib.escapeShellArg request} \
          "https://api.github.com/app/installations/$(cat ${secret "installation-id"})/access_tokens" \
        | jq -er .token \
        | install -m 0400 -o ${username} /dev/stdin "$RUNTIME_DIRECTORY/token"
    '';
  };
  attest = pkgs.writeShellApplication {
    name = "denylist-attest";
    text = ''
      GH_TOKEN=$(cat "$RUNTIME_DIRECTORY/token")
      export GH_TOKEN
      exec ${northBin}/north denylist attest --south ${south} ${
        lib.concatMapStringsSep " " (repo: "--repo tompassarelli/${repo}") repos
      }
    '';
  };
in
{
  options.myConfig.modules.denylist-attest = {
    enable = lib.mkEnableOption "denylist-attest: every five minutes, scan new claude/ branch tips of the public Autoland repositories against the private deny-list and post their denylist commit status as the Socrates Agent GitHub App; enable it on exactly one host, one with the south checkout";
    sopsFile = lib.mkOption {
      type = lib.types.path;
      description = "sops file holding the GitHub App's app_id, installation_id and private_key; only the unit's root mint step reads them, and it hands the attester a one-hour token limited to the Autoland repositories' statuses and workflows";
    };
  };
  config = lib.mkIf cfg.enable {
    sops.secrets =
      lib.genAttrs
        [ "denylist-attest-app-id" "denylist-attest-installation-id" "denylist-attest-private-key" ]
        (name: {
          inherit (cfg) sopsFile;
          key = lib.replaceStrings [ "-" ] [ "_" ] (lib.removePrefix "denylist-attest-" name);
        });
    systemd = {
      services.denylist-attest = {
        description = "Attest claude/ branch tips against the private deny-list";
        unitConfig.ConditionFileIsExecutable = "${northBin}/north";
        path = [
          pkgs.gh
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
          RuntimeDirectory = "denylist-attest";
          TimeoutStartSec = "4min";
          ExecStartPre = "+${lib.getExe mint}";
          ExecStart = jobRun "denylist-attest" (lib.getExe attest);
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
