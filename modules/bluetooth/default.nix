{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.bluetooth;
in
{
  options.myConfig.modules.bluetooth.enable = lib.mkEnableOption "bluetooth";
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.bluez ];
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
      settings.General = {
        Enable = "Source,Sink,Media,Socket";
        Experimental = true;
      };
    };
    services.blueman.enable = true;
  };
}
