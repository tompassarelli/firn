{ config, lib, ... }:

{
  config = lib.mkIf config.myConfig.modules.framework.enable {
    "boot" = {
      "extraModprobeConfig" = "options mt7925_common disable_clc=1\noptions mt7925e disable_aspm=1\n\n";
    };
    "services" = {
      "logind" = {
        "settings" = {
          "Login" = {
            "HandleLidSwitch" = "ignore";
            "HandleLidSwitchExternalPower" = "ignore";
          };
        };
      };
    };
  };
  options."myConfig"."modules"."framework"."enable" = lib.mkEnableOption "Framework Computer specific tools";
}
