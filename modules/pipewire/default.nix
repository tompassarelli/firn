{ config, lib, ... }:

{
  config = lib.mkIf config.myConfig.modules.pipewire.enable {
    "services" = {
      "pipewire" = {
        "alsa" = {
          "enable" = true;
          "support32Bit" = true;
        };
        "enable" = true;
        "pulse" = {
          "enable" = true;
        };
      };
    };
  };
  options."myConfig"."modules"."pipewire"."enable" = lib.mkEnableOption "PipeWire audio configuration";
}
