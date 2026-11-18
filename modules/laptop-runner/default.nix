{
  config,
  lib,
  pkgs,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.laptop-runner;
  username = config.myConfig.modules.users.username;
  description = "laptop-auto on the laptop: every 30 s apply the capacity mode, battery shedding and battery alerts (the ledger job runner went with the fleet, north#1650)";
in
{
  options.myConfig.modules.laptop-runner = {
    enable = lib.mkEnableOption description;
    placement = lib.mkOption {
      type = lib.types.str;
      default = "laptop";
      description = "this host's placement; laptop-auto runs only where it is laptop";
    };
  };
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.laptop-auto = lib.mkIf (cfg.placement == "laptop") {
          Unit = {
            Description = "Observe laptop gaming and seat activity for placement";
            ConditionFileIsExecutable = "${northBin}/north";
            X-SwitchMethod = "keep-old";
          };
          Service = {
            Type = "oneshot";
            Slice = "control.slice";
            ExecStart = "${northBin}/north capacity laptop-auto";
            TimeoutStartSec = "55s";
            Environment = "PATH=${
              lib.makeBinPath [
                pkgs.libnotify
                pkgs.python3
                pkgs.systemd
                pkgs.openssh
              ]
            }:${northBin}:/run/current-system/sw/bin";
          };
        };
        timers.laptop-auto = lib.mkIf (cfg.placement == "laptop") {
          Timer = {
            OnBootSec = "1min";
            OnUnitActiveSec = "30s";
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
