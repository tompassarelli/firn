{ config, lib, ... }:

{
  config = lib.mkIf config.myConfig.modules.printing.enable {
    "services" = {
      "avahi" = {
        "enable" = true;
        "nssmdns4" = true;
        "openFirewall" = true;
      };
      "printing" = {
        "enable" = true;
      };
    };
  };
  options."myConfig"."modules"."printing"."enable" = lib.mkEnableOption "CUPS printing service with network discovery";
}
