{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.socat.enable = lib.mkEnableOption "socat";
  config = lib.mkIf config.myConfig.modules.socat.enable {
    environment.systemPackages = [ pkgs.socat ];
  };
}
