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
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.bubblewrap ]; };
  options.myConfig.modules.bubblewrap.enable =
    lib.mkEnableOption "Enable bubblewrap sandbox (north readonly-shell requires bwrap)";
}
