{ config, lib, pkgs, ... }:

((cfg: {
  config = lib.mkIf cfg.enable {
    systemd.services.glide = {
      description = "Glide touchpad motion detection daemon";
      after = [ "kanata-main.service" ];
      wants = [ "kanata-main.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = lib.concatStringsSep " " [
          "${pkgs.glide}/bin/glide"
          "--device"
          cfg.device
          "--kanata-address"
          cfg.kanataAddress
          "--virtual-key"
          cfg.virtualKey
          "--motion-threshold"
          (toString cfg.motionThreshold)
          "--min-streak"
          (toString cfg.minStreak)
        ];
        Restart = "on-failure";
        RestartSec = 2;
        SupplementaryGroups = [ "input" ];
      };
    };
  };
}) config.myConfig.modules.glide)
