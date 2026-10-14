{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.ast-grep;
in
{
  options.myConfig.modules.ast-grep.enable = lib.mkEnableOption "ast-grep structural code search";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.ast-grep ]; };
}
