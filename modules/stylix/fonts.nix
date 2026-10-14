{ config, lib, ... }:
let
  cfg = config.myConfig.modules.stylix;
in
{
  config = lib.mkIf cfg.enable { fonts.fontconfig.enable = true; };
}
