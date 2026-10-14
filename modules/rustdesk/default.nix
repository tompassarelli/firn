{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.rustdesk;
in
{
  options.myConfig.modules.rustdesk.enable = lib.mkEnableOption "RustDesk remote desktop";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.rustdesk-flutter ]; };
}
