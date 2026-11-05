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
  mirror = "${homeDir}/.local/state/north/build-time/north/.git";
  description = "Daily Rust build-time measurement of north at main in a fresh detached checkout of the job's own mirror under heavy capacity, keeping one rolling split issue when a workspace nears its structure.toml threshold";
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
            ExecStartPre = "${pkgs.bash}/bin/bash -c 'test -d ${mirror} || ${pkgs.git}/bin/git clone --quiet --mirror https://github.com/tompassarelli/north.git ${mirror}'";
            ExecStart = jobRun "build-time" "${northBin}/north capacity host run --class heavy --owner build-time --timeout-seconds 3000 -- nix develop github:tompassarelli/north --command ${northBin}/north code-health build-time --repo ${mirror} --rev main --file";
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
