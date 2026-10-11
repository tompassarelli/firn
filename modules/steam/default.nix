{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.steam.enable {
    "programs" = {
      "steam" = {
        "enable" = true;
        "package" = pkgs.unstable.steam;
      };
    };
  };
  options."myConfig"."modules"."steam"."enable" = lib.mkEnableOption "Steam gaming platform";
}
