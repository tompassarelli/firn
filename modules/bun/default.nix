{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.bun.enable = lib.mkEnableOption "Bun JavaScript runtime and package manager";
  config = lib.mkIf config.myConfig.modules.bun.enable {
    environment.systemPackages = with pkgs; [ bun ];
  };
}
