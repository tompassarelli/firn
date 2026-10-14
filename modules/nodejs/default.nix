{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.nodejs;
in
{
  options.myConfig.modules.nodejs.enable = lib.mkEnableOption "Node.js runtime";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.nodejs ]; };
}
