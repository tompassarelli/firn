{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.glow.enable = lib.mkEnableOption "glow — terminal markdown renderer (tables, pager, dir browser)";
  config = lib.mkIf config.myConfig.modules.glow.enable {
    environment.systemPackages = with pkgs; [ glow ];
  };
}
