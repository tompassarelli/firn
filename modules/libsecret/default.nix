{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.libsecret;
in
{
  options.myConfig.modules.libsecret.enable =
    lib.mkEnableOption "secret-tool CLI for the login-keyring secret service";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.libsecret ]; };
}
