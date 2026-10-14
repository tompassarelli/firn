{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.emacs;
in
{
  options.myConfig.modules.emacs.enable = lib.mkEnableOption "GNU Emacs editor";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.emacs-pgtk ]; };
}
