{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.piper;
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.piper ];
    services.ratbagd.enable = true;
  };
  options.myConfig.modules.piper.enable =
    lib.mkEnableOption "gaming mouse configuration (Piper + ratbagd)";
}
