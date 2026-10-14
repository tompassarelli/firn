{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.steam;
in
{
  config = lib.mkIf cfg.enable {
    programs.steam = {
      enable = true;
      package = pkgs.unstable.steam;
    };
  };
  options.myConfig.modules.steam.enable = lib.mkEnableOption "Steam gaming platform";
}
