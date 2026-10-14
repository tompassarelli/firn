{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.bun;
in
{
  options.myConfig.modules.bun.enable =
    lib.mkEnableOption "Bun JavaScript runtime and package manager";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.bun ]; };
}
