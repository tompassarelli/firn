{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.bubblewrap;
in
{
  options.myConfig.modules.bubblewrap.enable =
    lib.mkEnableOption "Enable bubblewrap sandbox (north readonly-shell requires bwrap)";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.bubblewrap ]; };
}
