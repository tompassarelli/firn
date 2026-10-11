{ config, lib, ... }:

{
  config = lib.mkIf config.myConfig.modules.guix.enable {
    "services" = {
      "guix" = {
        "enable" = true;
      };
    };
  };
  options."myConfig"."modules"."guix"."enable" = lib.mkEnableOption "GNU Guix package manager";
}
