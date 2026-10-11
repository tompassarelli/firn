{ config, lib, ... }:

{
  config = lib.mkIf config.myConfig.modules.input.enable {
    "services" = {
      "libinput" = {
        "enable" = true;
      };
    };
  };
  options."myConfig"."modules"."input"."enable" = lib.mkEnableOption "touchpad support (libinput)";
}
