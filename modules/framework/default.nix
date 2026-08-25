{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.framework.enable = lib.mkEnableOption "Framework Computer specific tools";
  config = lib.mkIf config.myConfig.modules.framework.enable {
    services.logind.settings.Login = {
      HandleLidSwitch = "ignore";
      HandleLidSwitchExternalPower = "ignore";
    };
    boot.extraModprobeConfig = ''
      options mt7925_common disable_clc=1
      options mt7925e disable_aspm=1

    '';
  };
}
