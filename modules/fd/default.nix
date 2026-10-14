{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.fd;
in
{
  options.myConfig.modules.fd.enable = lib.mkEnableOption "fd file finder";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.fd ]; };
}
