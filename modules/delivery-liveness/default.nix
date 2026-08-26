{ config, lib, pkgs, ... }:

((username: {
  options.myConfig.modules.delivery-liveness.enable = lib.mkEnableOption "periodically build the committed Firn toplevel without switching";
  config = lib.mkIf config.myConfig.modules.delivery-liveness.enable {
    environment.etc."north/delivery-liveness-required".text = "1\n";
    home-manager.users.${username} = ({ config, ... }: {
      home.sessionVariables.NORTH_DELIVERY_LIVENESS_REQUIRED = "1";
      systemd.user.services.firn-delivery-liveness = {
        Unit = {
          Description = "Firn delivery liveness floor (non-switching)";
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${config.home.homeDirectory}/.local/bin/firn-liveness-floor";
          Environment = [
            "NORTH_BIN=${config.home.homeDirectory}/code/north/main/bin/north"
            "PATH=${config.home.homeDirectory}/.local/bin:${config.home.homeDirectory}/code/north/main/bin:${lib.makeBinPath (with pkgs; [
              bash
              coreutils
              gawk
              git
              nix
              python3
              util-linux
            ])}"
          ];
          TimeoutStartSec = "30m";
        };
      };
      systemd.user.timers.firn-delivery-liveness = {
        Unit = {
          Description = "Run Firn delivery liveness floor";
        };
        Timer = {
          OnCalendar = "*:0/30";
          Persistent = true;
          RandomizedDelaySec = "5m";
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
    });
  };
}) config.myConfig.modules.users.username)
