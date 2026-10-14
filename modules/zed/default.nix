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
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.zed-editor ]; };
  options.myConfig.modules.zed.enable = lib.mkEnableOption "Zed editor";
}
