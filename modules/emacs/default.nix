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
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.emacs-pgtk ]; };
  options.myConfig.modules.emacs.enable = lib.mkEnableOption "GNU Emacs editor";
}
