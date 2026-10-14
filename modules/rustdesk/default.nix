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
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.rustdesk-flutter ]; };
  options.myConfig.modules.rustdesk.enable = lib.mkEnableOption "RustDesk remote desktop";
}
