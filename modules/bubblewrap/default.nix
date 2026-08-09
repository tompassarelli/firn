{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.bubblewrap.enable = lib.mkEnableOption "Enable bubblewrap sandbox (north readonly-shell requires bwrap)";
  config = lib.mkIf config.myConfig.modules.bubblewrap.enable {
    environment.systemPackages = with pkgs; [ bubblewrap ];
  };
}
