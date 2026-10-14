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
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.pandoc ]; };
  options.myConfig.modules.pandoc.enable = lib.mkEnableOption "Pandoc document converter";
}
