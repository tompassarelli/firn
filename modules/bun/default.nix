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
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.bun ]; };
  options.myConfig.modules.bun.enable =
    lib.mkEnableOption "Bun JavaScript runtime and package manager";
}
