{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.mail.enable {
    "environment" = {
      "systemPackages" = [ pkgs.unstable.protonmail-desktop ];
    };
  };
  options."myConfig"."modules"."mail"."enable" = lib.mkEnableOption "email applications";
}
