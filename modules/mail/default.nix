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
  options.myConfig.modules.mail.enable = lib.mkEnableOption "email applications";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.unstable.protonmail-desktop ]; };
}
