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
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.libsecret ]; };
  options.myConfig.modules.libsecret.enable =
    lib.mkEnableOption "secret-tool CLI for the login-keyring secret service";
}
