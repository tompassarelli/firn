{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.pandoc;
in
{
  options.myConfig.modules.pandoc.enable = lib.mkEnableOption "Pandoc document converter";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.pandoc ]; };
}
