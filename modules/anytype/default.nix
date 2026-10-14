{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.anytype;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.anytype ]; };
  options.myConfig.modules.anytype.enable =
    lib.mkEnableOption "Anytype — local-first knowledge/notes workspace";
}
