{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.libsecret.enable = lib.mkEnableOption "secret-tool CLI for the login-keyring secret service";
  config = lib.mkIf config.myConfig.modules.libsecret.enable {
    environment.systemPackages = with pkgs; [ libsecret ];
  };
}
