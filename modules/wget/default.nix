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
  options.myConfig.modules.wget.enable = lib.mkEnableOption "wget download tool";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.wget ]; };
}
