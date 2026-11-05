{
  config,
  lib,
  jobRun,
  northBin,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.build-time;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  north = "${homeDir}/code/north/main";
  description = "Daily Rust build-time measurement of north at origin/main in a fresh detached checkout under heavy capacity, keeping one rolling split issue when a workspace nears its structure.toml threshold";
in
{
  options.myConfig.modules.build-time.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.build-time = {
          Unit = {
            Description = description;
            OnFailure = [ "update-notify@%n.service" ];
          };
          Service = {
            Type = "oneshot";
            Nice = 10;
            TimeoutStartSec = "60min";
            SuccessExitStatus = [ 1 ];
            Environment = [
              "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${northBin}:${homeDir}/.local/bin:${homeDir}/.local/share/firn/bin:${lib.makeBinPath [ pkgs.git ]}"
            ];
            ExecStart = jobRun "build-time" "${northBin}/north capacity host run --class heavy --owner build-time --timeout-seconds 3000 -- nix develop ${north} --command ${northBin}/north code-health build-time --repo ${north} --rev origin/main --file";
          };
        };
        timers.build-time = {
          Unit.Description = description;
          Timer = {
            OnCalendar = "*-*-* 21:00:00 UTC";
            RandomizedDelaySec = "20min";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
