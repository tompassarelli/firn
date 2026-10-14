{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.mail;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.unstable.protonmail-desktop ]; };
  options.myConfig.modules.mail.enable = lib.mkEnableOption "email applications";
}
