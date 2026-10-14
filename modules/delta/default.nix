{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.delta;
in
{
  options.myConfig.modules.delta.enable = lib.mkEnableOption "delta git diff viewer";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.delta ]; };
}
