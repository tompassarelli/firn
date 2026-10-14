{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.zed;
in
{
  options.myConfig.modules.zed.enable = lib.mkEnableOption "Zed editor";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.zed-editor ]; };
}
