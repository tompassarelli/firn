{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.rustdesk.enable {
    "environment" = {
      "systemPackages" = [ pkgs.rustdesk-flutter ];
    };
  };
  options."myConfig"."modules"."rustdesk"."enable" = lib.mkEnableOption "RustDesk remote desktop";
}
