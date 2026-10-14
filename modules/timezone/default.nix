{ config, lib, ... }:
let
  cfg = config.myConfig.modules.timezone;
in
{
  config = lib.mkIf cfg.enable { time.timeZone = config.myConfig.modules.timezone.zone; };
  imports = [
    {
      options.myConfig.modules.timezone.zone = lib.mkOption {
        default = "UTC";
        description = "IANA timezone — instance overrides per-host";
        type = lib.types.str;
      };
    }
  ];
  options.myConfig.modules.timezone.enable = lib.mkEnableOption "timezone configuration";
}
