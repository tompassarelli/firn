{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.musl.enable = lib.mkEnableOption "musl C compiler toolchain";
  config = lib.mkIf config.myConfig.modules.musl.enable {
    environment.systemPackages = with pkgs; [ musl.dev ];
  };
}
