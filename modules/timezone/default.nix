{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.timezone.enable = lib.mkEnableOption "timezone configuration";
  options.myConfig.modules.timezone.zone = lib.mkOption {
    type = lib.types.str;
    default = "Asia/Bangkok";
    description = "IANA timezone — instance overrides per-host";
  };
  config = lib.mkIf config.myConfig.modules.timezone.enable {
    time.timeZone = config.myConfig.modules.timezone.zone;
  };
}
