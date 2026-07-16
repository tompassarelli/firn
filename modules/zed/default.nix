{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.zed.enable = lib.mkEnableOption "Zed editor";
  config = lib.mkIf config.myConfig.modules.zed.enable {
    environment.systemPackages = [ pkgs.zed-editor ];
  };
}
