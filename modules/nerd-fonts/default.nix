{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.nerd-fonts;
in
{
  config = lib.mkIf cfg.enable { fonts.packages = [ pkgs.nerd-fonts.symbols-only ]; };
  options.myConfig.modules.nerd-fonts.enable = lib.mkEnableOption "Nerd Fonts symbols";
}
