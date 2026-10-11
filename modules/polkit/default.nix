{ config, lib, ... }:

{
  config = lib.mkIf config.myConfig.modules.polkit.enable {
    "security" = {
      "polkit" = {
        "enable" = true;
      };
    };
  };
  options."myConfig"."modules"."polkit"."enable" = lib.mkEnableOption "Polkit security configuration";
}
