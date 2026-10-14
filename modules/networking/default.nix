{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.networking;
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.networkmanagerapplet ];
    networking.networkmanager = {
      enable = true;
      logLevel = "DEBUG";
      unmanaged = [ "interface-name:wg*" ];
      wifi.powersave = false;
    };
  };
  options.myConfig.modules.networking.enable = lib.mkEnableOption "network configuration";
}
