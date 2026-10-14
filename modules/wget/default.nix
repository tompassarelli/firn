{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.wget;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.wget ]; };
  options.myConfig.modules.wget.enable = lib.mkEnableOption "wget download tool";
}
