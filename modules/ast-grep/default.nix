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
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.ast-grep ]; };
  options.myConfig.modules.ast-grep.enable = lib.mkEnableOption "ast-grep structural code search";
}
