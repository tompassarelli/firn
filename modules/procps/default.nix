{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.procps.enable = lib.mkEnableOption "procps";
  config = lib.mkIf config.myConfig.modules.procps.enable {
    environment.systemPackages = [ pkgs.procps ];
  };
}
