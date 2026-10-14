{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.uv;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.uv ]; };
  options.myConfig.modules.uv.enable = lib.mkEnableOption "uv Python package manager";
}
