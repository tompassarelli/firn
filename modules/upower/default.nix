{ config, lib, ... }:

{
  config = lib.mkIf config.myConfig.modules.upower.enable {
    "services" = {
      "upower" = {
        "enable" = true;
      };
    };
  };
  options."myConfig"."modules"."upower"."enable" = lib.mkEnableOption "UPower power management";
}
