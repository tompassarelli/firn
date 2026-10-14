{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.ghostscript;
in
{
  options.myConfig.modules.ghostscript.enable =
    lib.mkEnableOption "Ghostscript PostScript interpreter";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.ghostscript ]; };
}
