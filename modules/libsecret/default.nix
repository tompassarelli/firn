{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.libsecret.enable {
    "environment" = {
      "systemPackages" = [ pkgs.libsecret ];
    };
  };
  options."myConfig"."modules"."libsecret"."enable" = lib.mkEnableOption "secret-tool CLI for the login-keyring secret service";
}
