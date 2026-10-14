{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.gcc;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.gcc ]; };
  options.myConfig.modules.gcc.enable = lib.mkEnableOption "GNU C compiler";
}
