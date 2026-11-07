{
  config,
  lib,
  pkgs,
  jobRun,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.makgora-goals-perf;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  description = "makgora-goals-perf: daily re-record of Mak'gora's playable-bot-four frame run into ~/.local/state/makgora/goals/classic.perf, the file its frame goals read";
  record = "${homeDir}/.local/state/makgora/goals/classic.perf";
  run = pkgs.writeShellScript "makgora-goals-perf" ''
    set -eu
    mkdir -p "$(dirname ${record})"
    tmp="${record}.new"
    cd ${homeDir}/code/makgora/main
    ${northBin}/north capacity dev-shell run --dir . -- bash -c "cd ts && bun wisp perf playable-bot-four --samples --out '$tmp'"
    mv "$tmp" ${record}
  '';
in
{
  options.myConfig.modules.makgora-goals-perf.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.makgora-goals-perf = {
          Unit = {
            Description = description;
            OnFailure = [ "update-notify@%n.service" ];
            X-SwitchMethod = "keep-old";
          };
          Service = {
            Type = "oneshot";
            Nice = 10;
            TimeoutStartSec = "30min";
            Restart = "on-failure";
            RestartSec = "10min";
            Environment = [
              "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.local/share/firn/bin:${northBin}:${
                lib.makeBinPath [
                  pkgs.git
                  pkgs.coreutils
                  pkgs.bash
                ]
              }"
            ];
            ExecStart = jobRun "makgora-goals-perf" "${northBin}/north capacity host run --class heavy --owner makgora-goals-perf --timeout-seconds 1500 -- ${run}";
          };
        };
        timers.makgora-goals-perf = {
          Unit.Description = description;
          Timer = {
            OnCalendar = "daily";
            Persistent = true;
            RandomizedDelaySec = "1h";
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
